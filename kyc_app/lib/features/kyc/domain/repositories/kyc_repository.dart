import '../entities/kyc_application.dart';
import '../entities/kyc_draft.dart';
import '../entities/kyc_enums.dart';
import '../entities/personal_details.dart';

typedef UploadProgress = void Function(int sent, int total);

/// Everything the KYC flow needs, independent of Dio / SharedPreferences / file system.
abstract interface class KycRepository {
  /* ------------------------------- Remote ------------------------------- */

  /// Current server application, or null when the user never started one.
  Future<KycApplication?> fetchApplication();

  Future<KycStatusInfo> fetchStatus();

  /// Polls the status until the reviewer decides (APPROVED / REJECTED / RESUBMISSION_REQUESTED). Errors are emitted as stream
  /// errors and polling continues.
  Stream<KycStatusInfo> pollStatus(Duration interval);

  /// Syncs partial details + wizard step to the server (enables cross-device resume).
  Future<KycApplication> saveRemoteDraft(PersonalDetails details, {KycStep? step});

  /// Uploads one image (multipart). Returns a presigned view URL.
  Future<String?> uploadDocument(DocumentType type, String filePath);

  /// Submits details + any images the server doesn't have yet in one multipart request.
  Future<KycApplication> submit({
    required PersonalDetails details,
    required Map<DocumentType, String> files,
    UploadProgress? onProgress,
  });

  /* -------------------------------- Local ------------------------------- */

  Future<KycDraft?> loadLocalDraft(String userId);

  Future<void> saveLocalDraft(String userId, KycDraft draft);

  /// Removes the draft and all cached photos for [userId].
  Future<void> clearLocalDraft(String userId);

  /// Compresses a freshly captured photo into app storage; returns the stored path.
  Future<String> storeCapturedImage({
    required String userId,
    required DocumentType type,
    required String sourcePath,
  });

  Future<void> deleteLocalImage(String path);
}
