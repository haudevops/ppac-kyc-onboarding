import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_application.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_draft.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/domain/entities/personal_details.dart';
import 'package:kyc_app/features/kyc/domain/services/kyc_progress.dart';

import 'fixtures.dart';

void main() {
  group('KycResumeResolver', () {
    test('local edits override server values field by field', () {
      final result = KycResumeResolver.resolve(
        local: const KycDraft(details: PersonalDetails(city: 'Hanoi')),
        remote: const KycApplication(
          status: KycStatus.draft,
          details: PersonalDetails(fullName: 'Server Name', city: 'Da Nang'),
        ),
        remoteAvailable: true,
        now: kNow,
      );
      expect(result.draft.details.fullName, 'Server Name');
      expect(result.draft.details.city, 'Hanoi');
      expect(result.draft.step, KycStep.personalDetails);
      expect(result.isResume, isTrue);
    });

    test('reuses documents the server already has when there is no local file', () {
      final result = KycResumeResolver.resolve(
        local: null,
        remote: KycApplication(
          status: KycStatus.draft,
          details: completeDetails(),
          documentUrls: const {
            DocumentType.idFront: 'https://r2/front',
            DocumentType.idBack: 'https://r2/back',
            DocumentType.selfie: 'https://r2/selfie',
          },
          currentStep: 'review',
        ),
        remoteAvailable: true,
        now: kNow,
      );
      expect(result.draft.documents[DocumentType.selfie]?.uploadState, DocumentUploadState.uploaded);
      expect(result.draft.step, KycStep.review);
    });

    test('re-queues a local photo marked uploaded that the server no longer has', () {
      final local = completeDraft().withDocument(
        const KycDocument(type: DocumentType.selfie, localPath: '/x/selfie.jpg', uploadState: DocumentUploadState.uploaded),
      );
      final result = KycResumeResolver.resolve(
        local: local,
        remote: const KycApplication(status: KycStatus.draft),
        remoteAvailable: true,
        now: kNow,
      );
      expect(result.draft.documents[DocumentType.selfie]?.uploadState, DocumentUploadState.pending);
    });

    test('decided or pending applications open the status screen', () {
      for (final status in [
        KycStatus.submitted,
        KycStatus.processing,
        KycStatus.approved,
        KycStatus.rejected,
        KycStatus.resubmissionRequested,
      ]) {
        final result = KycResumeResolver.resolve(
          local: completeDraft(step: KycStep.document),
          remote: KycApplication(status: status),
          remoteAvailable: true,
          now: kNow,
        );
        expect(result.draft.step, KycStep.verification, reason: status.name);
      }
    });

    test('offline uses the last known status', () {
      final result = KycResumeResolver.resolve(
        local: completeDraft(step: KycStep.verification).copyWith(lastKnownStatus: KycStatus.submitted),
        remote: null,
        remoteAvailable: false,
        now: kNow,
      );
      expect(result.status, KycStatus.submitted);
      expect(result.draft.step, KycStep.verification);
    });
  });

  test('firstIncompleteStep walks the wizard in order', () {
    expect(firstIncompleteStep(const KycDraft(), now: kNow), KycStep.personalDetails);
    final draft = completeDraft();
    expect(firstIncompleteStep(draft, now: kNow), KycStep.review);
    expect(
      firstIncompleteStep(draft.copyWith(documents: {...draft.documents}..remove(DocumentType.idBack)), now: kNow),
      KycStep.document,
    );
    // A passport does not need a back side.
    final passport = draft.copyWith(
      details: draft.details.mergeWith(const PersonalDetails(idType: IdType.passport, idNumber: 'C1234567')),
      documents: {...draft.documents}..remove(DocumentType.idBack),
    );
    expect(firstIncompleteStep(passport, now: kNow), KycStep.review);
  });
}
