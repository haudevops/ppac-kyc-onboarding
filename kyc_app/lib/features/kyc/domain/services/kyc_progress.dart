import '../entities/kyc_application.dart';
import '../entities/kyc_draft.dart';
import '../entities/kyc_enums.dart';
import '../entities/personal_details.dart';
import '../validation/personal_details_validator.dart';

/// The furthest wizard step the user is allowed to be on, given what is filled in.
KycStep firstIncompleteStep(KycDraft draft, {DateTime? now}) {
  if (PersonalDetailsValidator.validate(draft.details, now: now).isNotEmpty) return KycStep.personalDetails;
  final missing = draft.missingDocuments;
  if (missing.any((t) => t != DocumentType.selfie)) return KycStep.document;
  if (missing.contains(DocumentType.selfie)) return KycStep.selfie;
  return KycStep.review;
}

class KycResumeResult {
  const KycResumeResult({required this.draft, required this.status, required this.isResume});

  final KycDraft draft;
  final KycStatus status;

  /// True when we restored meaningful progress (used to greet the user).
  final bool isResume;
}

/// Reconciles the locally cached draft with the server snapshot when the app starts.
///
/// Rules:
///  * Status: the server is authoritative; offline we fall back to the last known status.
///  * Fields: server values as base, local non-empty values on top (the device holds the
///    user's latest unsynced edits).
///  * Images: a local file wins (it may not be uploaded yet); otherwise reuse the server copy.
///    A local file marked "uploaded" that the server no longer has is re-queued.
///  * Step: pending/decided applications go to the status screen; otherwise the saved step,
///    clamped to the first incomplete step (never land on "Review" with missing data).
abstract final class KycResumeResolver {
  static KycResumeResult resolve({
    required KycDraft? local,
    required KycApplication? remote,
    required bool remoteAvailable,
    DateTime? now,
  }) {
    final status = remoteAvailable
        ? (remote?.status ?? KycStatus.notStarted)
        : (local?.lastKnownStatus ?? KycStatus.notStarted);

    final details = (remote?.details ?? const PersonalDetails()).mergeWith(local?.details);

    final documents = <DocumentType, KycDocument>{};
    for (final type in DocumentType.values) {
      final localDoc = local?.documents[type];
      final remoteUrl = remote?.documentUrls[type];

      if (localDoc?.localPath != null) {
        var uploadState = localDoc!.uploadState;
        if (uploadState == DocumentUploadState.uploading) uploadState = DocumentUploadState.pending;
        if (remoteAvailable && uploadState == DocumentUploadState.uploaded && remoteUrl == null) {
          uploadState = DocumentUploadState.pending;
        }
        documents[type] = KycDocument(
          type: type,
          localPath: localDoc.localPath,
          remoteUrl: remoteUrl,
          uploadState: uploadState,
        );
      } else if (remoteUrl != null) {
        documents[type] = KycDocument(type: type, remoteUrl: remoteUrl, uploadState: DocumentUploadState.uploaded);
      }
    }

    var draft = KycDraft(details: details, documents: documents, lastKnownStatus: status, updatedAt: now);

    final KycStep step;
    if (status.isPending || status.isDecided) {
      step = KycStep.verification;
    } else {
      var preferred = local?.step ?? KycStep.fromName(remote?.currentStep) ?? KycStep.personalDetails;
      if (preferred == KycStep.verification) preferred = KycStep.review;
      final limit = firstIncompleteStep(draft, now: now);
      step = preferred.index > limit.index ? limit : preferred;
    }
    draft = draft.copyWith(step: step);

    final hadLocalProgress = local != null && !local.isEmpty;
    final hadRemoteProgress = remote != null && status.isEditable && !draft.isEmpty;
    return KycResumeResult(draft: draft, status: status, isResume: hadLocalProgress || hadRemoteProgress);
  }
}
