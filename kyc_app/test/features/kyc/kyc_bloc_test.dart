import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/error/app_exception.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_application.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_draft.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/domain/entities/personal_details.dart';
import 'package:kyc_app/features/kyc/domain/repositories/kyc_repository.dart';
import 'package:kyc_app/features/kyc/presentation/bloc/kyc_bloc.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _MockKycRepository extends Mock implements KycRepository {}

void main() {
  late _MockKycRepository repository;

  setUpAll(() {
    registerFallbackValue(const KycDraft());
    registerFallbackValue(const PersonalDetails());
    registerFallbackValue(DocumentType.idFront);
    registerFallbackValue(KycStep.review);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<DocumentType, String>{});
  });

  setUp(() {
    repository = _MockKycRepository();
    when(() => repository.saveLocalDraft(any(), any())).thenAnswer((_) async {});
    when(() => repository.clearLocalDraft(any())).thenAnswer((_) async {});
    when(() => repository.saveRemoteDraft(any(), step: any(named: 'step')))
        .thenAnswer((_) async => const KycApplication(status: KycStatus.draft));
  });

  KycBloc buildBloc() => KycBloc(
        repository: repository,
        userId: 'user-1',
        pollInterval: const Duration(milliseconds: 10),
        autosaveDebounce: Duration.zero,
        clock: () => kNow,
      );

  group('resume', () {
    blocTest<KycBloc, KycState>(
      'restores the locally saved step',
      build: () {
        when(() => repository.loadLocalDraft('user-1')).thenAnswer((_) async => completeDraft(step: KycStep.selfie));
        when(() => repository.fetchApplication()).thenAnswer((_) async => const KycApplication(status: KycStatus.draft));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const KycStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, KycLoadStatus.ready);
        expect(bloc.state.step, KycStep.selfie);
        expect(bloc.state.serverStatus, KycStatus.draft);
        expect(bloc.state.draft.details.fullName, 'Alice Nguyen');
        expect(bloc.state.message?.isError, isFalse);
      },
    );

    blocTest<KycBloc, KycState>(
      'never resumes past the first incomplete step',
      build: () {
        final draft = completeDraft(step: KycStep.review);
        when(() => repository.loadLocalDraft(any())).thenAnswer(
          (_) async => draft.copyWith(documents: {...draft.documents}..remove(DocumentType.selfie)),
        );
        when(() => repository.fetchApplication()).thenAnswer((_) async => null);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const KycStarted()),
      verify: (bloc) => expect(bloc.state.step, KycStep.selfie),
    );

    blocTest<KycBloc, KycState>(
      'works offline from the local draft',
      build: () {
        when(() => repository.loadLocalDraft(any())).thenAnswer((_) async => completeDraft(step: KycStep.document));
        when(() => repository.fetchApplication())
            .thenThrow(const AppException(AppErrorType.network, 'offline'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const KycStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, KycLoadStatus.ready);
        expect(bloc.state.isOffline, isTrue);
        expect(bloc.state.step, KycStep.document);
      },
    );

    blocTest<KycBloc, KycState>(
      'fails when offline and nothing is saved locally',
      build: () {
        when(() => repository.loadLocalDraft(any())).thenAnswer((_) async => null);
        when(() => repository.fetchApplication())
            .thenThrow(const AppException(AppErrorType.network, 'offline'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const KycStarted()),
      verify: (bloc) => expect(bloc.state.loadStatus, KycLoadStatus.failure),
    );

    blocTest<KycBloc, KycState>(
      'a pending application goes to the status screen and polls until approved',
      build: () {
        when(() => repository.loadLocalDraft(any())).thenAnswer((_) async => null);
        when(() => repository.fetchApplication())
            .thenAnswer((_) async => KycApplication(status: KycStatus.processing, details: completeDetails()));
        when(() => repository.pollStatus(any()))
            .thenAnswer((_) => Stream.value(const KycStatusInfo(status: KycStatus.approved)));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const KycStarted()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.verification);
        expect(bloc.state.serverStatus, KycStatus.approved);
        expect(bloc.state.isPolling, isFalse);
        // PII is removed from the device once approved.
        verify(() => repository.clearLocalDraft('user-1')).called(1);
      },
    );
  });

  group('personal details', () {
    blocTest<KycBloc, KycState>(
      'invalid details stay on step 1 with field errors',
      build: buildBloc,
      seed: () => const KycState(loadStatus: KycLoadStatus.ready),
      act: (bloc) => bloc.add(const KycPersonalDetailsSubmitted(PersonalDetails(fullName: 'A'))),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.personalDetails);
        expect(bloc.state.fieldErrors.keys, containsAll(<String>['fullName', 'dateOfBirth', 'idNumber']));
        verifyNever(() => repository.saveRemoteDraft(any(), step: any(named: 'step')));
      },
    );

    blocTest<KycBloc, KycState>(
      'valid details move to the document step and sync the draft',
      build: buildBloc,
      seed: () => const KycState(loadStatus: KycLoadStatus.ready),
      act: (bloc) => bloc.add(KycPersonalDetailsSubmitted(completeDetails())),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.document);
        expect(bloc.state.fieldErrors, isEmpty);
        verify(() => repository.saveLocalDraft('user-1', any())).called(greaterThanOrEqualTo(1));
        verify(() => repository.saveRemoteDraft(any(), step: KycStep.document)).called(1);
      },
    );
  });

  group('submit', () {
    blocTest<KycBloc, KycState>(
      'sends only images the server does not have, then polls the decision',
      build: () {
        when(
          () => repository.submit(
            details: any(named: 'details'),
            files: any(named: 'files'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => const KycApplication(status: KycStatus.submitted));
        when(() => repository.pollStatus(any())).thenAnswer(
          (_) => Stream.fromIterable(const [
            KycStatusInfo(status: KycStatus.processing),
            KycStatusInfo(status: KycStatus.rejected, rejectionReason: 'Blurry photo'),
          ]),
        );
        return buildBloc();
      },
      seed: () {
        final draft = completeDraft(step: KycStep.review);
        return KycState(
          loadStatus: KycLoadStatus.ready,
          serverStatus: KycStatus.draft,
          draft: draft.withDocument(
            draft.documents[DocumentType.idFront]!.copyWith(uploadState: DocumentUploadState.uploaded),
          ),
        );
      },
      act: (bloc) => bloc.add(const KycSubmitted()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        final files = verify(
          () => repository.submit(
            details: any(named: 'details'),
            files: captureAny(named: 'files'),
            onProgress: any(named: 'onProgress'),
          ),
        ).captured.single as Map<DocumentType, String>;
        expect(files.keys, unorderedEquals([DocumentType.idBack, DocumentType.selfie]));

        expect(bloc.state.step, KycStep.verification);
        expect(bloc.state.serverStatus, KycStatus.rejected);
        expect(bloc.state.rejectionReason, 'Blurry photo');
        expect(bloc.state.isSubmitting, isFalse);
      },
    );

    blocTest<KycBloc, KycState>(
      'KYC_INCOMPLETE from the server sends the user to the missing step',
      build: () {
        when(
          () => repository.submit(
            details: any(named: 'details'),
            files: any(named: 'files'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenThrow(
          const AppException(
            AppErrorType.validation,
            'KYC application is incomplete.',
            code: 'KYC_INCOMPLETE',
            statusCode: 422,
            details: {'fieldIssues': <Object>[], 'missingDocuments': ['SELFIE']},
          ),
        );
        return buildBloc();
      },
      seed: () => KycState(
        loadStatus: KycLoadStatus.ready,
        serverStatus: KycStatus.draft,
        draft: completeDraft(step: KycStep.review),
      ),
      act: (bloc) => bloc.add(const KycSubmitted()),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.selfie);
        expect(bloc.state.isSubmitting, isFalse);
        expect(bloc.state.draft.documents[DocumentType.selfie]?.uploadState, DocumentUploadState.pending);
        expect(bloc.state.message?.isError, isTrue);
      },
    );

    blocTest<KycBloc, KycState>(
      'blocks submission locally when a photo is missing',
      build: buildBloc,
      seed: () {
        final draft = completeDraft(step: KycStep.review);
        return KycState(
          loadStatus: KycLoadStatus.ready,
          serverStatus: KycStatus.draft,
          draft: draft.copyWith(documents: {...draft.documents}..remove(DocumentType.idBack)),
        );
      },
      act: (bloc) => bloc.add(const KycSubmitted()),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.document);
        verifyNever(
          () => repository.submit(
            details: any(named: 'details'),
            files: any(named: 'files'),
            onProgress: any(named: 'onProgress'),
          ),
        );
      },
    );
  });

  group('review outcomes', () {
    blocTest<KycBloc, KycState>(
      'polling stops on a resubmission request and exposes what to redo',
      build: () {
        when(() => repository.pollStatus(any())).thenAnswer(
          (_) => Stream.value(
            const KycStatusInfo(
              status: KycStatus.resubmissionRequested,
              rejectionReason: 'Blurry selfie',
              resubmissionItems: [ResubmissionItem.selfie],
            ),
          ),
        );
        return buildBloc();
      },
      seed: () => KycState(
        loadStatus: KycLoadStatus.ready,
        serverStatus: KycStatus.processing,
        draft: completeDraft(step: KycStep.verification),
      ),
      act: (bloc) => bloc.add(const KycStatusPollingStarted()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.serverStatus, KycStatus.resubmissionRequested);
        expect(bloc.state.step, KycStep.verification);
        expect(bloc.state.resubmissionItems, [ResubmissionItem.selfie]);
        expect(bloc.state.isPolling, isFalse);
        expect(bloc.state.canEdit, isTrue);
      },
    );

    blocTest<KycBloc, KycState>(
      'fix and resubmit opens the requested step and discards the flagged photo',
      build: () {
        when(() => repository.deleteLocalImage(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      seed: () {
        final draft = completeDraft(step: KycStep.verification);
        return KycState(
          loadStatus: KycLoadStatus.ready,
          serverStatus: KycStatus.resubmissionRequested,
          rejectionReason: 'Blurry selfie',
          resubmissionItems: const [ResubmissionItem.selfie],
          draft: draft.withDocument(
            draft.documents[DocumentType.selfie]!.copyWith(uploadState: DocumentUploadState.uploaded),
          ),
        );
      },
      act: (bloc) => bloc.add(const KycResubmitRequested()),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.selfie);
        expect(bloc.state.draft.documents.containsKey(DocumentType.selfie), isFalse);
        expect(bloc.state.draft.documents.containsKey(DocumentType.idFront), isTrue);
        expect(bloc.state.showRejectionBanner, isTrue);
        expect(bloc.state.requestedOn(KycStep.selfie), [ResubmissionItem.selfie]);
        verify(() => repository.deleteLocalImage(any())).called(1);
      },
    );

    blocTest<KycBloc, KycState>(
      'a final rejection cannot be resubmitted',
      build: buildBloc,
      seed: () => KycState(
        loadStatus: KycLoadStatus.ready,
        serverStatus: KycStatus.rejected,
        rejectionReason: 'Fraud suspected',
        draft: completeDraft(step: KycStep.verification),
      ),
      act: (bloc) => bloc
        ..add(const KycResubmitRequested())
        ..add(const KycStepSelected(KycStep.personalDetails)),
      verify: (bloc) {
        expect(bloc.state.step, KycStep.verification);
        expect(bloc.state.canEdit, isFalse);
      },
    );
  });
}
