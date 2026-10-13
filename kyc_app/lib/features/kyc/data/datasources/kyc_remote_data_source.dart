import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/kyc_application.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/entities/personal_details.dart';
import '../models/kyc_mappers.dart';

/// HTTP calls to the KYC endpoints of kyc_service.
class KycRemoteDataSource {
  KycRemoteDataSource(this._api);

  final ApiClient _api;

  /// GET /kyc -> `{ status, allowedActions, application | null }`
  Future<KycApplication?> getApplication() async {
    final data = await _api.get('/kyc');
    final application = data['application'];
    return application is Map<String, dynamic> ? kycApplicationFromJson(application) : null;
  }

  /// GET /kyc/status
  Future<KycStatusInfo> getStatus() async => kycStatusFromJson(await _api.get('/kyc/status'));

  /// PUT /kyc/draft (partial details + resume pointer)
  Future<KycApplication> saveDraft(PersonalDetails details, {KycStep? step}) async {
    final data = await _api.put(
      '/kyc/draft',
      data: {
        ...details.normalized().toFieldMap(),
        if (step != null) 'currentStep': step.name,
      },
    );
    return kycApplicationFromJson(data['application'] as Map<String, dynamic>);
  }

  /// POST /kyc/documents/:type (multipart, field "file")
  Future<String?> uploadDocument(DocumentType type, String filePath) async {
    final data = await _api.postMultipart(
      '/kyc/documents/${type.pathSegment}',
      buildForm: () async => FormData.fromMap({'file': await _imagePart(type, filePath)}),
    );
    final document = data['document'];
    return document is Map ? document['url'] as String? : null;
  }

  /// POST /kyc/submit (multipart: personal-details fields + idFront / idBack / selfie)
  Future<KycApplication> submit({
    required PersonalDetails details,
    required Map<DocumentType, String> files,
    ProgressCallback? onSendProgress,
  }) async {
    final data = await _api.postMultipart(
      '/kyc/submit',
      onSendProgress: onSendProgress,
      // Safe to retry: a duplicate submit is answered with 409 KYC_NOT_EDITABLE.
      retryable: true,
      buildForm: () async {
        final form = FormData();
        details.normalized().toFieldMap().forEach((key, value) => form.fields.add(MapEntry(key, value)));
        for (final entry in files.entries) {
          form.files.add(MapEntry(entry.key.multipartField, await _imagePart(entry.key, entry.value)));
        }
        return form;
      },
    );
    return kycApplicationFromJson(data['application'] as Map<String, dynamic>);
  }

  Future<MultipartFile> _imagePart(DocumentType type, String path) {
    return MultipartFile.fromFile(
      path,
      filename: '${type.pathSegment}.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    );
  }
}
