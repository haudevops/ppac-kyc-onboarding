import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/event_transformers.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/ui_message.dart';
import '../../domain/entities/kyc_application.dart';
import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/entities/personal_details.dart';
import '../../domain/repositories/kyc_repository.dart';
import '../../domain/services/kyc_progress.dart';
import '../../domain/validation/personal_details_validator.dart';

part 'kyc_event.dart';
part 'kyc_state.dart';

/// Drives the whole onboarding wizard:
///
///   Resume -> 1 Personal details -> 2 Document -> 3 Selfie -> 4 Review -> 5 Submit + status
///
/// * Every meaningful change is persisted locally (SharedPreferences + photo files) so the
///   flow survives the app being killed; details + step are also synced to the backend
///   (best effort) for cross-device resume.
/// * Photos are compressed and uploaded in the background as soon as they are captured;
///   the final submit only sends what the server does not have yet.
/// * After submitting, the status is polled (rxdart) until APPROVED / REJECTED.
class KycBloc extends Bloc<KycEvent, KycState> {
  KycBloc({
    required KycRepository repository,
    required String userId,
    Duration pollInterval = const Duration(seconds: 2),
    Duration autosaveDebounce = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  })  : _repository = repository,
        _userId = userId,
        _pollInterval = pollInterval,
        _now = clock ?? DateTime.now,
        super(const KycState()) {
    on<KycStarted>(_onStarted, transformer: droppable());
    on<KycPersonalDetailsChanged>(_onDetailsChanged, transformer: debounceRestartable(autosaveDebounce));
    on<KycPersonalDetailsSubmitted>(_onDetailsSubmitted);
    on<KycDocumentCaptured>(_onDocumentCaptured);
    on<KycDocumentUploadRetried>(_onUploadRetried);
    on<KycStepContinued>(_onStepContinued);
    on<KycStepBackRequested>(_onStepBack);
    on<KycStepSelected>(_onStepSelected);
    on<KycSubmitted>(_onSubmitted, transformer: droppable());
    on<KycStatusPollingStarted>(_onPollingStarted, transformer: restartable());
    on<KycStatusRefreshRequested>(_onRefreshRequested, transformer: droppable());
    on<KycResubmitRequested>(_onResubmitRequested);
  }

  final KycRepository _repository;
  final String _userId;
  final Duration _pollInterval;
  final DateTime Function() _now;

  /// Set once the application is approved and the local draft was wiped.
  bool _draftCleared = false;

  /* ------------------------------------------------------------------ */
  /* Resume                                                             */
  /* ------------------------------------------------------------------ */

  Future<void> _onStarted(KycStarted event, Emitter<KycState> emit) async {
    emit(state.copyWith(loadStatus: KycLoadStatus.loading, loadError: null));

    final local = await _safeLoadLocal();

    KycApplication? remote;
    AppException? remoteError;
    var remoteAvailable = false;
    try {
      remote = await _repository.fetchApplication();
      remoteAvailable = true;
    } on AppException catch (e) {
      remoteError = e;
    }

    if (!remoteAvailable && local == null) {
      emit(state.copyWith(loadStatus: KycLoadStatus.failure, loadError: remoteError?.message));
      return;
    }

    final resumed = KycResumeResolver.resolve(
      local: local,
      remote: remote,
      remoteAvailable: remoteAvailable,
      now: _now(),
    );

    UiMessage? message;
    if (!remoteAvailable) {
      message = UiMessage.error('You are offline - showing the progress saved on this device.');
    } else if (resumed.isResume && resumed.status.isEditable && resumed.draft.step != KycStep.verification) {
      message = UiMessage.info('Welcome back! We restored your progress (${resumed.draft.step.label}).');
    }

    emit(state.copyWith(
      loadStatus: KycLoadStatus.ready,
      draft: resumed.draft,
      serverStatus: resumed.status,
      rejectionReason: remote?.rejectionReason,
      resubmissionItems: remote?.resubmissionItems ?? const [],
      isOffline: !remoteAvailable,
      message: message,
    ));
    await _persist();

    if (resumed.status.isPending && remoteAvailable) add(const KycStatusPollingStarted());
    if (resumed.status == KycStatus.approved) await _clearLocalDraft();
  }

  /* ------------------------------------------------------------------ */
  /* Step 1 - personal details                                          */
  /* ------------------------------------------------------------------ */

  Future<void> _onDetailsChanged(KycPersonalDetailsChanged event, Emitter<KycState> emit) async {
    if (!state.canEdit || state.loadStatus != KycLoadStatus.ready) return;

    // Clear server/local errors only for the fields the user just changed.
    final before = state.draft.details.toFieldMap();
    final after = event.details.toFieldMap();
    final errors = Map.of(state.fieldErrors)..removeWhere((field, _) => before[field] != after[field]);

    emit(state.copyWith(draft: state.draft.copyWith(details: event.details), fieldErrors: errors));
    await _persist();
  }

  Future<void> _onDetailsSubmitted(KycPersonalDetailsSubmitted event, Emitter<KycState> emit) async {
    if (!state.canEdit) return;

    final details = event.details.normalized();
    final errors = PersonalDetailsValidator.validate(details, now: _now());
    if (errors.isNotEmpty) {
      emit(state.copyWith(
        draft: state.draft.copyWith(details: details),
        fieldErrors: errors,
        message: UiMessage.error('Please fix the highlighted fields.'),
      ));
      await _persist();
      return;
    }

    emit(state.copyWith(
      draft: state.draft.copyWith(details: details, step: KycStep.document),
      fieldErrors: const {},
    ));
    await _persist();
    await _syncRemoteDraft(emit);
  }

  /* ------------------------------------------------------------------ */
  /* Steps 2 & 3 - document and selfie capture                          */
  /* ------------------------------------------------------------------ */

  Future<void> _onDocumentCaptured(KycDocumentCaptured event, Emitter<KycState> emit) async {
    if (!state.canEdit) return;
    final type = event.type;

    emit(state.copyWith(processingDocuments: {...state.processingDocuments, type}));
    final String storedPath;
    try {
      storedPath = await _repository.storeCapturedImage(userId: _userId, type: type, sourcePath: event.sourcePath);
    } on AppException catch (e) {
      emit(state.copyWith(
        processingDocuments: {...state.processingDocuments}..remove(type),
        message: UiMessage.error(e.message),
      ));
      return;
    } on Object {
      emit(state.copyWith(
        processingDocuments: {...state.processingDocuments}..remove(type),
        message: UiMessage.error('Could not save the photo. Please try again.'),
      ));
      return;
    }

    final previousPath = state.draft.documents[type]?.localPath;
    emit(state.copyWith(
      processingDocuments: {...state.processingDocuments}..remove(type),
      draft: state.draft.withDocument(KycDocument(type: type, localPath: storedPath)),
    ));
    await _persist();
    if (previousPath != null && previousPath != storedPath) {
      unawaited(_repository.deleteLocalImage(previousPath));
    }

    await _uploadInBackground(type, storedPath, emit);
  }

  Future<void> _onUploadRetried(KycDocumentUploadRetried event, Emitter<KycState> emit) async {
    final path = state.draft.documents[event.type]?.localPath;
    if (path == null || !state.canEdit) return;
    await _uploadInBackground(event.type, path, emit);
  }

  /// Uploads right after capture so the final submit is fast and the server-side draft is
  /// complete. Failures are non-fatal: the file is re-sent with the submit request.
  Future<void> _uploadInBackground(DocumentType type, String path, Emitter<KycState> emit) async {
    _updateDocument(emit, type, path, (d) => d.copyWith(uploadState: DocumentUploadState.uploading));
    try {
      final url = await _repository.uploadDocument(type, path);
      _updateDocument(emit, type, path, (d) => d.copyWith(uploadState: DocumentUploadState.uploaded, remoteUrl: url));
      if (state.isOffline) emit(state.copyWith(isOffline: false));
    } on AppException catch (e) {
      _updateDocument(emit, type, path, (d) => d.copyWith(uploadState: DocumentUploadState.failed));
      if (e.code == 'KYC_NOT_EDITABLE' && !isClosed) add(const KycStatusRefreshRequested());
    }
    await _persist();
  }

  /// Applies [update] only if the document was not replaced by a newer capture meanwhile.
  void _updateDocument(
    Emitter<KycState> emit,
    DocumentType type,
    String path,
    KycDocument Function(KycDocument current) update,
  ) {
    final current = state.draft.documents[type];
    if (current == null || current.localPath != path) return;
    emit(state.copyWith(draft: state.draft.withDocument(update(current))));
  }

  /* ------------------------------------------------------------------ */
  /* Navigation                                                         */
  /* ------------------------------------------------------------------ */

  Future<void> _onStepContinued(KycStepContinued event, Emitter<KycState> emit) async {
    if (!state.canEdit) return;
    switch (state.step) {
      case KycStep.document:
        final missing = state.draft.missingDocuments.where((t) => t != DocumentType.selfie).toList();
        if (missing.isNotEmpty) {
          emit(state.copyWith(
            message: UiMessage.error('Please capture the ${missing.map((t) => t.label.toLowerCase()).join(' and ')}.'),
          ));
          return;
        }
        await _goTo(KycStep.selfie, emit);
      case KycStep.selfie:
        if (!state.draft.hasDocument(DocumentType.selfie)) {
          emit(state.copyWith(message: UiMessage.error('Please take a selfie to continue.')));
          return;
        }
        await _goTo(KycStep.review, emit);
      case KycStep.personalDetails:
      case KycStep.review:
      case KycStep.verification:
        return;
    }
  }

  Future<void> _onStepBack(KycStepBackRequested event, Emitter<KycState> emit) async {
    if (!state.canEdit) return;
    final step = state.step;
    if (step == KycStep.personalDetails || step == KycStep.verification) return;
    await _goTo(KycStep.values[step.index - 1], emit);
  }

  Future<void> _onStepSelected(KycStepSelected event, Emitter<KycState> emit) async {
    final target = event.step;
    if (!state.canEdit || target == KycStep.verification || target == state.step) return;
    final limit = firstIncompleteStep(state.draft, now: _now());
    // Going back is always allowed; going forward only up to the first incomplete step.
    if (target.index > state.step.index && target.index > limit.index) return;
    await _goTo(target, emit);
  }

  Future<void> _goTo(KycStep step, Emitter<KycState> emit) async {
    emit(state.copyWith(draft: state.draft.copyWith(step: step)));
    await _persist();
    await _syncRemoteDraft(emit);
  }

  /* ------------------------------------------------------------------ */
  /* Step 4 - submit                                                    */
  /* ------------------------------------------------------------------ */

  Future<void> _onSubmitted(KycSubmitted event, Emitter<KycState> emit) async {
    if (!state.canEdit) return;
    final draft = state.draft;

    final errors = PersonalDetailsValidator.validate(draft.details, now: _now());
    if (errors.isNotEmpty) {
      emit(state.copyWith(
        fieldErrors: errors,
        draft: draft.copyWith(step: KycStep.personalDetails),
        message: UiMessage.error('Some details need your attention.'),
      ));
      return;
    }
    final missing = draft.missingDocuments;
    if (missing.isNotEmpty) {
      emit(state.copyWith(
        draft: draft.copyWith(step: _stepForMissingDocuments(missing)),
        message: UiMessage.error('Please capture all required photos.'),
      ));
      return;
    }

    // Only send images the server doesn't already have.
    final files = <DocumentType, String>{
      for (final type in draft.requiredDocuments)
        if (draft.documents[type]?.localPath != null &&
            draft.documents[type]!.uploadState != DocumentUploadState.uploaded)
          type: draft.documents[type]!.localPath!,
    };

    emit(state.copyWith(isSubmitting: true, uploadProgress: files.isEmpty ? null : 0.0, fieldErrors: const {}));

    var lastPercent = -1;
    try {
      final application = await _repository.submit(
        details: draft.details,
        files: files,
        onProgress: (sent, total) {
          if (total <= 0) return;
          final percent = sent * 100 ~/ total;
          if (percent - lastPercent >= 5 || percent == 100) {
            lastPercent = percent;
            emit(state.copyWith(uploadProgress: percent / 100));
          }
        },
      );

      final documents = {
        for (final entry in state.draft.documents.entries)
          entry.key: files.containsKey(entry.key)
              ? entry.value.copyWith(uploadState: DocumentUploadState.uploaded)
              : entry.value,
      };
      emit(state.copyWith(
        isSubmitting: false,
        uploadProgress: null,
        serverStatus: application.status,
        rejectionReason: null,
        resubmissionItems: const [],
        draft: state.draft.copyWith(
          documents: documents,
          step: KycStep.verification,
          lastKnownStatus: application.status,
        ),
        message: UiMessage.info('Submitted! We are verifying your identity.'),
      ));
      await _persist();
      if (!isClosed) add(const KycStatusPollingStarted());
    } on AppException catch (e) {
      await _handleSubmitError(e, emit);
    }
  }

  Future<void> _handleSubmitError(AppException e, Emitter<KycState> emit) async {
    switch (e.code) {
      case 'KYC_INCOMPLETE':
      case 'VALIDATION_ERROR':
        final fieldErrors = e.fieldErrors;
        final missing = e.missingDocuments.map(DocumentType.fromApi).whereType<DocumentType>().toList();

        // The server is missing images we believed were uploaded: queue them again.
        final documents = Map.of(state.draft.documents);
        for (final type in missing) {
          final doc = documents[type];
          if (doc == null) continue;
          if (doc.localPath != null) {
            documents[type] = doc.copyWith(uploadState: DocumentUploadState.pending);
          } else {
            documents.remove(type);
          }
        }

        final step = fieldErrors.isNotEmpty
            ? KycStep.personalDetails
            : missing.isNotEmpty
                ? _stepForMissingDocuments(missing)
                : state.step;
        emit(state.copyWith(
          isSubmitting: false,
          uploadProgress: null,
          fieldErrors: fieldErrors,
          draft: state.draft.copyWith(documents: documents, step: step),
          message: UiMessage.error(e.message),
        ));
        await _persist();

      case 'KYC_NOT_EDITABLE':
        // Typically a retried submit whose first attempt already succeeded.
        emit(state.copyWith(isSubmitting: false, uploadProgress: null));
        await _refreshStatus(emit);

      default:
        emit(state.copyWith(
          isSubmitting: false,
          uploadProgress: null,
          message: UiMessage.error(
            e.isConnectivity ? 'Could not submit - check your connection and try again. Nothing was lost.' : e.message,
          ),
        ));
    }
  }

  KycStep _stepForMissingDocuments(List<DocumentType> missing) =>
      missing.any((t) => t != DocumentType.selfie) ? KycStep.document : KycStep.selfie;

  /* ------------------------------------------------------------------ */
  /* Step 5 - verification status                                       */
  /* ------------------------------------------------------------------ */

  Future<void> _onPollingStarted(KycStatusPollingStarted event, Emitter<KycState> emit) async {
    emit(state.copyWith(isPolling: true, pollingError: false));
    await emit.forEach<KycStatusInfo>(
      _repository.pollStatus(_pollInterval),
      onData: _stateWithStatus,
      onError: (error, stackTrace) => state.copyWith(pollingError: true),
    );
    emit(state.copyWith(isPolling: false));
    await _afterStatusChange();
  }

  Future<void> _onRefreshRequested(KycStatusRefreshRequested event, Emitter<KycState> emit) async {
    if (!state.serverStatus.isPending && state.step != KycStep.verification) return;
    await _refreshStatus(emit);
  }

  Future<void> _refreshStatus(Emitter<KycState> emit) async {
    try {
      final info = await _repository.fetchStatus();
      emit(_stateWithStatus(info).copyWith(isOffline: false));
      await _afterStatusChange();
      if (info.status.isPending && !state.isPolling && !isClosed) add(const KycStatusPollingStarted());
    } on AppException catch (e) {
      emit(state.copyWith(message: UiMessage.error(e.message)));
    }
  }

  KycState _stateWithStatus(KycStatusInfo info) {
    final status = info.status;
    var step = state.step;
    // The user already left the status screen to fix a resubmission request: stay in the wizard.
    final fixingResubmission = status == KycStatus.resubmissionRequested &&
        state.serverStatus == KycStatus.resubmissionRequested &&
        step != KycStep.verification;

    if (status.isPending || status.isDecided) {
      if (!fixingResubmission) step = KycStep.verification;
    } else if (step == KycStep.verification) {
      step = KycStep.review; // re-opened on the server (e.g. from another device)
    }

    return state.copyWith(
      serverStatus: status,
      rejectionReason: info.rejectionReason,
      resubmissionItems: info.resubmissionItems,
      lastCheckedAt: _now(),
      pollingError: false,
      draft: state.draft.copyWith(step: step, lastKnownStatus: status),
    );
  }

  Future<void> _afterStatusChange() async {
    if (state.serverStatus == KycStatus.approved) {
      await _clearLocalDraft();
    } else {
      await _persist();
    }
  }

  /// RESUBMISSION_REQUESTED -> back into the wizard at the first item the reviewer asked for.
  /// Photos the reviewer flagged are discarded locally so they must be retaken (the backend
  /// drops its copies when the application is re-opened). REJECTED is final: nothing to do.
  Future<void> _onResubmitRequested(KycResubmitRequested event, Emitter<KycState> emit) async {
    if (state.serverStatus != KycStatus.resubmissionRequested) return;
    final items = state.resubmissionItems;

    final documents = Map.of(state.draft.documents);
    for (final item in items) {
      final type = item.documentType;
      final doc = type == null ? null : documents[type];
      // Keep a photo retaken after the request (not uploaded yet); drop the reviewed one.
      if (type == null || doc == null || doc.uploadState != DocumentUploadState.uploaded) continue;
      documents.remove(type);
      final path = doc.localPath;
      if (path != null) unawaited(_repository.deleteLocalImage(path));
    }

    final target = items.isEmpty
        ? KycStep.personalDetails
        : items.map((i) => i.step).reduce((a, b) => a.index <= b.index ? a : b);
    emit(state.copyWith(
      draft: state.draft.copyWith(documents: documents, step: target),
      message: UiMessage.info(
        items.isEmpty ? 'Update your information, then submit again.' : 'Please update: ${items.map((i) => i.label).join(', ')}.',
      ),
    ));
    await _persist();
  }

  /* ------------------------------------------------------------------ */
  /* Persistence helpers                                                */
  /* ------------------------------------------------------------------ */

  Future<KycDraft?> _safeLoadLocal() async {
    try {
      return await _repository.loadLocalDraft(_userId);
    } on Object {
      return null;
    }
  }

  /// Local storage failures must never break the flow.
  Future<void> _persist() async {
    if (_draftCleared) return;
    try {
      await _repository.saveLocalDraft(_userId, state.draft.copyWith(updatedAt: _now()));
    } on Object {
      // ignore
    }
  }

  /// PII minimisation: once approved, nothing needs to stay on the device.
  Future<void> _clearLocalDraft() async {
    _draftCleared = true;
    try {
      await _repository.clearLocalDraft(_userId);
    } on Object {
      // ignore
    }
  }

  /// Best-effort server sync of details + current step (cross-device resume).
  /// The local draft stays the source of truth until submit, so failures are silent.
  Future<void> _syncRemoteDraft(Emitter<KycState> emit) async {
    if (!state.serverStatus.isEditable) return;
    try {
      final application = await _repository.saveRemoteDraft(state.draft.details, step: state.step);
      // A resubmission request is re-opened (RESUBMISSION_REQUESTED -> DRAFT) by the first edit.
      emit(state.copyWith(serverStatus: application.status, isOffline: false));
    } on AppException catch (e) {
      if (e.code == 'KYC_NOT_EDITABLE' && !isClosed) add(const KycStatusRefreshRequested());
    }
  }
}
