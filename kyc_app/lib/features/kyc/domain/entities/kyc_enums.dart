/// Server-side KYC status (mirrors the backend state machine).
enum KycStatus {
  notStarted('NOT_STARTED'),
  draft('DRAFT'),
  submitted('SUBMITTED'),
  processing('PROCESSING'),
  approved('APPROVED'),

  /// Final negative decision - cannot be resubmitted.
  rejected('REJECTED'),

  /// The reviewer asks the user to redo specific items (see [ResubmissionItem]).
  resubmissionRequested('RESUBMISSION_REQUESTED');

  const KycStatus(this.apiValue);

  final String apiValue;

  static KycStatus fromApi(String? value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return KycStatus.notStarted;
  }

  /// The user may still change data (a resubmission request is re-opened on the first edit).
  bool get isEditable => this == notStarted || this == draft || this == resubmissionRequested;

  /// Waiting for the reviewer.
  bool get isPending => this == submitted || this == processing;

  /// No further transition possible.
  bool get isFinal => this == approved || this == rejected;

  /// The reviewer has answered (polling can stop).
  bool get isDecided => isFinal || this == resubmissionRequested;
}

/// Wizard steps. The index is persisted so an interrupted flow can resume.
enum KycStep {
  personalDetails('Details'),
  document('Document'),
  selfie('Selfie'),
  review('Review'),
  verification('Status');

  const KycStep(this.label);

  final String label;

  static KycStep? fromName(String? name) {
    for (final step in values) {
      if (step.name == name) return step;
    }
    return null;
  }
}

enum DocumentType {
  idFront('ID_FRONT', 'id-front', 'idFront', 'Front side'),
  idBack('ID_BACK', 'id-back', 'idBack', 'Back side'),
  selfie('SELFIE', 'selfie', 'selfie', 'Selfie');

  const DocumentType(this.apiValue, this.pathSegment, this.multipartField, this.label);

  /// Value used in JSON (`ID_FRONT`).
  final String apiValue;

  /// Value used in URLs (`/kyc/documents/id-front`).
  final String pathSegment;

  /// Field name in the multipart submit request.
  final String multipartField;
  final String label;

  static DocumentType? fromApi(String? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

enum IdType {
  nationalId('NATIONAL_ID', 'National ID card'),
  passport('PASSPORT', 'Passport'),
  driverLicense('DRIVER_LICENSE', "Driver's license");

  const IdType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static IdType? fromApi(String? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }

  /// A passport only has a photo page; cards need both sides.
  List<DocumentType> get requiredDocuments => this == passport
      ? const [DocumentType.idFront, DocumentType.selfie]
      : const [DocumentType.idFront, DocumentType.idBack, DocumentType.selfie];
}

enum Gender {
  male('MALE', 'Male'),
  female('FEMALE', 'Female'),
  other('OTHER', 'Other');

  const Gender(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static Gender? fromApi(String? value) {
    for (final g in values) {
      if (g.apiValue == value) return g;
    }
    return null;
  }
}

enum DocumentUploadState { pending, uploading, uploaded, failed }

/// What a reviewer can ask the user to redo.
enum ResubmissionItem {
  personalDetails('PERSONAL_DETAILS', 'Personal details', KycStep.personalDetails, null),
  idFront('ID_FRONT', 'Front of your ID', KycStep.document, DocumentType.idFront),
  idBack('ID_BACK', 'Back of your ID', KycStep.document, DocumentType.idBack),
  selfie('SELFIE', 'Selfie', KycStep.selfie, DocumentType.selfie);

  const ResubmissionItem(this.apiValue, this.label, this.step, this.documentType);

  final String apiValue;
  final String label;

  /// Wizard step where the item is fixed.
  final KycStep step;

  /// Photo that must be retaken, if any.
  final DocumentType? documentType;

  static List<ResubmissionItem> parseAll(Object? raw) {
    if (raw is! List) return const [];
    final items = <ResubmissionItem>[];
    for (final value in raw) {
      for (final item in values) {
        if (item.apiValue == value) items.add(item);
      }
    }
    return items;
  }
}
