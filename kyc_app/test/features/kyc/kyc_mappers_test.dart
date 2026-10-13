import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/features/kyc/data/models/kyc_mappers.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_draft.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';

import 'fixtures.dart';

void main() {
  test('local draft round-trips with relative image paths', () {
    const root = '/data';
    final draft = completeDraft(step: KycStep.selfie).withDocument(
      const KycDocument(
        type: DocumentType.idFront,
        localPath: '/data/kyc_drafts/user-1/id-front.jpg',
        uploadState: DocumentUploadState.uploading,
      ),
    );

    final json = kycDraftToJson(draft, relativize: (abs) => abs.substring(root.length + 1));
    expect((json['documents'] as List).first['localPath'], startsWith('kyc_drafts/'));

    final restored = kycDraftFromJson(json, resolvePath: (rel) => '$root/$rel');
    expect(restored.details, draft.details);
    expect(restored.step, KycStep.selfie);
    // An interrupted upload becomes pending again.
    expect(restored.documents[DocumentType.idFront]?.uploadState, DocumentUploadState.pending);
    expect(restored.documents.length, 3);
  });

  test('images whose file disappeared are dropped', () {
    final json = kycDraftToJson(completeDraft(), relativize: (abs) => abs);
    final restored = kycDraftFromJson(json, resolvePath: (_) => null);
    expect(restored.documents, isEmpty);
    expect(restored.details.fullName, 'Alice Nguyen');
  });

  test('parses the API application payload', () {
    final app = kycApplicationFromJson({
      'status': 'RESUBMISSION_REQUESTED',
      'resubmissionItems': ['SELFIE', 'NOT_A_THING', 'ID_FRONT'],
      'currentStep': 'review',
      'rejectionReason': 'Expired document',
      'personalDetails': {'fullName': 'Alice Nguyen', 'dateOfBirth': '1990-05-20', 'idType': 'PASSPORT', 'city': null},
      'documents': [
        {'type': 'ID_FRONT', 'url': 'https://example.com/front'},
        {'type': 'UNKNOWN', 'url': 'https://example.com/x'},
      ],
    });
    expect(app.status, KycStatus.resubmissionRequested);
    expect(app.resubmissionItems, [ResubmissionItem.selfie, ResubmissionItem.idFront]);
    expect(app.details.idType, IdType.passport);
    expect(app.details.dateOfBirth, DateTime(1990, 5, 20));
    expect(app.details.city, isNull);
    expect(app.documentUrls.keys, [DocumentType.idFront]);
  });
}
