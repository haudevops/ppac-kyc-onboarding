import 'package:equatable/equatable.dart';

import 'kyc_enums.dart';
import 'personal_details.dart';

/// Server-side snapshot of the user's application (GET /kyc).
class KycApplication extends Equatable {
  const KycApplication({
    required this.status,
    this.id,
    this.details = const PersonalDetails(),
    this.documentUrls = const {},
    this.currentStep,
    this.rejectionReason,
    this.resubmissionItems = const [],
    this.submittedAt,
    this.reviewedAt,
    this.updatedAt,
  });

  final KycStatus status;

  /// Application id (reference shown to the user / support).
  final String? id;
  final PersonalDetails details;

  /// Presigned view URLs of the documents the server already has.
  final Map<DocumentType, String> documentUrls;
  final String? currentStep;

  /// Reviewer message (REJECTED / RESUBMISSION_REQUESTED, kept until the next submit).
  final String? rejectionReason;
  final List<ResubmissionItem> resubmissionItems;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? updatedAt;

  @override
  List<Object?> get props =>
      [status, id, details, documentUrls, currentStep, rejectionReason, resubmissionItems, submittedAt, reviewedAt, updatedAt];
}

/// Lightweight status (GET /kyc/status), used for polling.
class KycStatusInfo extends Equatable {
  const KycStatusInfo({
    required this.status,
    this.rejectionReason,
    this.resubmissionItems = const [],
    this.reviewedAt,
    this.updatedAt,
  });

  final KycStatus status;
  final String? rejectionReason;
  final List<ResubmissionItem> resubmissionItems;
  final DateTime? reviewedAt;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [status, rejectionReason, resubmissionItems, reviewedAt, updatedAt];
}
