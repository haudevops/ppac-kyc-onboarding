import 'package:rxdart/rxdart.dart';

import '../../domain/entities/kyc_application.dart';
import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/entities/personal_details.dart';
import '../../domain/repositories/kyc_repository.dart';
import '../datasources/kyc_local_data_source.dart';
import '../datasources/kyc_remote_data_source.dart';

class KycRepositoryImpl implements KycRepository {
  KycRepositoryImpl({required KycRemoteDataSource remote, required KycLocalDataSource local})
      : _remote = remote,
        _local = local;

  final KycRemoteDataSource _remote;
  final KycLocalDataSource _local;

  @override
  Future<KycApplication?> fetchApplication() => _remote.getApplication();

  @override
  Future<KycStatusInfo> fetchStatus() => _remote.getStatus();

  /// Immediate first check, then every [interval]. `exhaustMap` never overlaps requests
  /// on a slow network; `takeWhileInclusive` emits the decision and completes.
  @override
  Stream<KycStatusInfo> pollStatus(Duration interval) {
    return Stream<void>.periodic(interval)
        .startWith(null)
        .exhaustMap((_) => Stream.fromFuture(fetchStatus()))
        .takeWhileInclusive((info) => !info.status.isDecided);
  }

  @override
  Future<KycApplication> saveRemoteDraft(PersonalDetails details, {KycStep? step}) =>
      _remote.saveDraft(details, step: step);

  @override
  Future<String?> uploadDocument(DocumentType type, String filePath) => _remote.uploadDocument(type, filePath);

  @override
  Future<KycApplication> submit({
    required PersonalDetails details,
    required Map<DocumentType, String> files,
    UploadProgress? onProgress,
  }) {
    return _remote.submit(details: details, files: files, onSendProgress: onProgress);
  }

  @override
  Future<KycDraft?> loadLocalDraft(String userId) => _local.load(userId);

  @override
  Future<void> saveLocalDraft(String userId, KycDraft draft) => _local.save(userId, draft);

  @override
  Future<void> clearLocalDraft(String userId) => _local.clear(userId);

  @override
  Future<String> storeCapturedImage({required String userId, required DocumentType type, required String sourcePath}) {
    return _local.storeImage(userId: userId, type: type, sourcePath: sourcePath);
  }

  @override
  Future<void> deleteLocalImage(String path) => _local.deleteImage(path);
}
