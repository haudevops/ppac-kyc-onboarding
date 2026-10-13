part of 'kyc_bloc.dart';

sealed class KycEvent extends Equatable {
  const KycEvent();

  @override
  List<Object?> get props => [];
}

/// Load local draft + server snapshot and resume where the user left off.
final class KycStarted extends KycEvent {
  const KycStarted();
}

/// Step 1: a field changed (debounced autosave to local storage).
final class KycPersonalDetailsChanged extends KycEvent {
  const KycPersonalDetailsChanged(this.details);

  final PersonalDetails details;

  @override
  List<Object?> get props => [details];
}

/// Step 1: "Continue" pressed.
final class KycPersonalDetailsSubmitted extends KycEvent {
  const KycPersonalDetailsSubmitted(this.details);

  final PersonalDetails details;

  @override
  List<Object?> get props => [details];
}

/// Steps 2-3: a photo was accepted on the camera screen.
final class KycDocumentCaptured extends KycEvent {
  const KycDocumentCaptured({required this.type, required this.sourcePath});

  final DocumentType type;
  final String sourcePath;

  @override
  List<Object?> get props => [type, sourcePath];
}

/// Retry a background upload that failed.
final class KycDocumentUploadRetried extends KycEvent {
  const KycDocumentUploadRetried(this.type);

  final DocumentType type;

  @override
  List<Object?> get props => [type];
}

/// "Continue" on the document / selfie steps.
final class KycStepContinued extends KycEvent {
  const KycStepContinued();
}

/// System back / "Back" button inside the wizard.
final class KycStepBackRequested extends KycEvent {
  const KycStepBackRequested();
}

/// Jump to a step (e.g. "Edit" on the review screen).
final class KycStepSelected extends KycEvent {
  const KycStepSelected(this.step);

  final KycStep step;

  @override
  List<Object?> get props => [step];
}

/// Step 4: submit for verification.
final class KycSubmitted extends KycEvent {
  const KycSubmitted();
}

/// Step 5: poll the verification status until a decision is made.
final class KycStatusPollingStarted extends KycEvent {
  const KycStatusPollingStarted();
}

/// Manual refresh / app returned to foreground.
final class KycStatusRefreshRequested extends KycEvent {
  const KycStatusRefreshRequested();
}

/// Rejected -> go back into the wizard to fix and resubmit.
final class KycResubmitRequested extends KycEvent {
  const KycResubmitRequested();
}
