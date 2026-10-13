import 'package:equatable/equatable.dart';

import 'kyc_enums.dart';
import 'personal_details.dart';

/// A captured image. [localPath] is the compressed copy kept in the app's documents
/// directory; [uploadState] tracks whether the backend already has it.
class KycDocument extends Equatable {
  const KycDocument({
    required this.type,
    this.localPath,
    this.remoteUrl,
    this.uploadState = DocumentUploadState.pending,
  });

  final DocumentType type;
  final String? localPath;

  /// Short-lived presigned URL returned by the API (display only, never persisted).
  final String? remoteUrl;
  final DocumentUploadState uploadState;

  /// The document can be used for submission (we have the file, or the server has it).
  bool get isAvailable => localPath != null || uploadState == DocumentUploadState.uploaded;

  KycDocument copyWith({String? localPath, String? remoteUrl, DocumentUploadState? uploadState}) {
    return KycDocument(
      type: type,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      uploadState: uploadState ?? this.uploadState,
    );
  }

  @override
  List<Object?> get props => [type, localPath, remoteUrl, uploadState];
}

/// Everything needed to rebuild the wizard after the app is killed:
/// form inputs, captured images and the current step.
class KycDraft extends Equatable {
  const KycDraft({
    this.details = const PersonalDetails(),
    this.documents = const {},
    this.step = KycStep.personalDetails,
    this.lastKnownStatus = KycStatus.notStarted,
    this.updatedAt,
  });

  final PersonalDetails details;
  final Map<DocumentType, KycDocument> documents;
  final KycStep step;

  /// Last server status seen, used when the app starts offline.
  final KycStatus lastKnownStatus;
  final DateTime? updatedAt;

  IdType get effectiveIdType => details.idType ?? IdType.nationalId;

  List<DocumentType> get requiredDocuments => effectiveIdType.requiredDocuments;

  bool hasDocument(DocumentType type) => documents[type]?.isAvailable ?? false;

  List<DocumentType> get missingDocuments => requiredDocuments.where((t) => !hasDocument(t)).toList();

  bool get isEmpty => details.isEmpty && documents.isEmpty;

  KycDraft withDocument(KycDocument document) => copyWith(documents: {...documents, document.type: document});

  KycDraft copyWith({
    PersonalDetails? details,
    Map<DocumentType, KycDocument>? documents,
    KycStep? step,
    KycStatus? lastKnownStatus,
    DateTime? updatedAt,
  }) {
    return KycDraft(
      details: details ?? this.details,
      documents: documents ?? this.documents,
      step: step ?? this.step,
      lastKnownStatus: lastKnownStatus ?? this.lastKnownStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [details, documents, step, lastKnownStatus, updatedAt];
}
