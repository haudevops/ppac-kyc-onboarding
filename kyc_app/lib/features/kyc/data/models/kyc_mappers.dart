import '../../domain/entities/kyc_application.dart';
import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/entities/personal_details.dart';

/* -------------------------------------------------------------------------- */
/* API JSON                                                                   */
/* -------------------------------------------------------------------------- */

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Parses `data.application` from GET /kyc, PUT /kyc/draft and POST /kyc/submit.
KycApplication kycApplicationFromJson(Map<String, dynamic> json) {
  final urls = <DocumentType, String>{};
  for (final raw in (json['documents'] as List<dynamic>? ?? const [])) {
    if (raw is! Map) continue;
    final type = DocumentType.fromApi(raw['type'] as String?);
    final url = raw['url'];
    if (type != null && url is String) urls[type] = url;
  }

  final details = json['personalDetails'];
  return KycApplication(
    status: KycStatus.fromApi(json['status'] as String?),
    id: json['id'] as String?,
    details: details is Map ? PersonalDetails.fromFieldMap(Map<String, dynamic>.from(details)) : const PersonalDetails(),
    documentUrls: urls,
    currentStep: json['currentStep'] as String?,
    rejectionReason: json['rejectionReason'] as String?,
    resubmissionItems: ResubmissionItem.parseAll(json['resubmissionItems']),
    submittedAt: _date(json['submittedAt']),
    reviewedAt: _date(json['reviewedAt']),
    updatedAt: _date(json['updatedAt']),
  );
}

/// Parses `data` of GET /kyc/status.
KycStatusInfo kycStatusFromJson(Map<String, dynamic> json) => KycStatusInfo(
      status: KycStatus.fromApi(json['status'] as String?),
      rejectionReason: json['rejectionReason'] as String?,
      resubmissionItems: ResubmissionItem.parseAll(json['resubmissionItems']),
      reviewedAt: _date(json['reviewedAt']),
      updatedAt: _date(json['updatedAt']),
    );

/* -------------------------------------------------------------------------- */
/* Local draft JSON (SharedPreferences)                                       */
/* -------------------------------------------------------------------------- */

const int kDraftSchemaVersion = 1;

/// [relativize] turns an absolute image path into one relative to the app documents
/// directory: on iOS the container path changes between app updates, so absolute paths
/// must never be persisted.
Map<String, dynamic> kycDraftToJson(KycDraft draft, {required String? Function(String absolutePath) relativize}) {
  return {
    'version': kDraftSchemaVersion,
    'step': draft.step.name,
    'lastKnownStatus': draft.lastKnownStatus.apiValue,
    'updatedAt': (draft.updatedAt ?? DateTime.now()).toIso8601String(),
    'details': draft.details.toFieldMap(),
    'documents': [
      for (final doc in draft.documents.values)
        if (doc.localPath != null || doc.uploadState == DocumentUploadState.uploaded)
          {
            'type': doc.type.apiValue,
            'localPath': doc.localPath == null ? null : relativize(doc.localPath!),
            'uploadState': doc.uploadState.name,
          },
    ],
  };
}

/// [resolvePath] maps a stored relative path back to an absolute path, or null when the
/// file no longer exists (e.g. the OS cleared storage) - that image is then dropped.
KycDraft kycDraftFromJson(Map<String, dynamic> json, {required String? Function(String relativePath) resolvePath}) {
  final documents = <DocumentType, KycDocument>{};
  for (final raw in (json['documents'] as List<dynamic>? ?? const [])) {
    if (raw is! Map) continue;
    final type = DocumentType.fromApi(raw['type'] as String?);
    if (type == null) continue;

    final relative = raw['localPath'] as String?;
    final localPath = relative == null ? null : resolvePath(relative);
    var uploadState = _uploadState(raw['uploadState'] as String?);
    // An upload interrupted by the app being killed is simply pending again.
    if (uploadState == DocumentUploadState.uploading) uploadState = DocumentUploadState.pending;
    if (localPath == null && uploadState != DocumentUploadState.uploaded) continue;

    documents[type] = KycDocument(type: type, localPath: localPath, uploadState: uploadState);
  }

  final details = json['details'];
  return KycDraft(
    details: details is Map ? PersonalDetails.fromFieldMap(Map<String, dynamic>.from(details)) : const PersonalDetails(),
    documents: documents,
    step: KycStep.fromName(json['step'] as String?) ?? KycStep.personalDetails,
    lastKnownStatus: KycStatus.fromApi(json['lastKnownStatus'] as String?),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

DocumentUploadState _uploadState(String? name) {
  for (final state in DocumentUploadState.values) {
    if (state.name == name) return state;
  }
  return DocumentUploadState.pending;
}
