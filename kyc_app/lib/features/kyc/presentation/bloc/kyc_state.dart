part of 'kyc_bloc.dart';

enum KycLoadStatus { initial, loading, ready, failure }

const Object _unset = Object();

final class KycState extends Equatable {
  const KycState({
    this.loadStatus = KycLoadStatus.initial,
    this.draft = const KycDraft(),
    this.serverStatus = KycStatus.notStarted,
    this.rejectionReason,
    this.resubmissionItems = const [],
    this.fieldErrors = const {},
    this.processingDocuments = const {},
    this.isSubmitting = false,
    this.uploadProgress,
    this.isPolling = false,
    this.pollingError = false,
    this.lastCheckedAt,
    this.isOffline = false,
    this.message,
    this.loadError,
  });

  final KycLoadStatus loadStatus;

  /// Wizard data (also what is persisted locally).
  final KycDraft draft;
  final KycStatus serverStatus;

  /// Reviewer message for REJECTED / RESUBMISSION_REQUESTED (kept until the next submit).
  final String? rejectionReason;

  /// What the reviewer asked to redo.
  final List<ResubmissionItem> resubmissionItems;

  /// API field name -> error (from local validation or the backend).
  final Map<String, String> fieldErrors;

  /// Photos currently being compressed/stored.
  final Set<DocumentType> processingDocuments;
  final bool isSubmitting;

  /// 0..1 while the submit request uploads, null otherwise.
  final double? uploadProgress;
  final bool isPolling;

  /// Last poll failed (shown as "reconnecting...").
  final bool pollingError;
  final DateTime? lastCheckedAt;

  /// Started without reaching the backend (working from the local draft).
  final bool isOffline;
  final UiMessage? message;
  final String? loadError;

  KycStep get step => draft.step;

  bool get canEdit => serverStatus.isEditable && !isSubmitting;

  /// Show the reviewer's feedback banner inside the wizard while fixing a resubmission request.
  bool get showRejectionBanner => rejectionReason != null && step != KycStep.verification && serverStatus.isEditable;

  /// Requested items fixed on [step] (to highlight them).
  List<ResubmissionItem> requestedOn(KycStep step) =>
      showRejectionBanner ? resubmissionItems.where((i) => i.step == step).toList() : const [];

  KycState copyWith({
    KycLoadStatus? loadStatus,
    KycDraft? draft,
    KycStatus? serverStatus,
    Object? rejectionReason = _unset,
    List<ResubmissionItem>? resubmissionItems,
    Map<String, String>? fieldErrors,
    Set<DocumentType>? processingDocuments,
    bool? isSubmitting,
    Object? uploadProgress = _unset,
    bool? isPolling,
    bool? pollingError,
    Object? lastCheckedAt = _unset,
    bool? isOffline,
    Object? message = _unset,
    Object? loadError = _unset,
  }) {
    return KycState(
      loadStatus: loadStatus ?? this.loadStatus,
      draft: draft ?? this.draft,
      serverStatus: serverStatus ?? this.serverStatus,
      rejectionReason: identical(rejectionReason, _unset) ? this.rejectionReason : rejectionReason as String?,
      resubmissionItems: resubmissionItems ?? this.resubmissionItems,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      processingDocuments: processingDocuments ?? this.processingDocuments,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      uploadProgress: identical(uploadProgress, _unset) ? this.uploadProgress : uploadProgress as double?,
      isPolling: isPolling ?? this.isPolling,
      pollingError: pollingError ?? this.pollingError,
      lastCheckedAt: identical(lastCheckedAt, _unset) ? this.lastCheckedAt : lastCheckedAt as DateTime?,
      isOffline: isOffline ?? this.isOffline,
      message: identical(message, _unset) ? this.message : message as UiMessage?,
      loadError: identical(loadError, _unset) ? this.loadError : loadError as String?,
    );
  }

  @override
  List<Object?> get props => [
        loadStatus,
        draft,
        serverStatus,
        rejectionReason,
        resubmissionItems,
        fieldErrors,
        processingDocuments,
        isSubmitting,
        uploadProgress,
        isPolling,
        pollingError,
        lastCheckedAt,
        isOffline,
        message,
        loadError,
      ];
}
