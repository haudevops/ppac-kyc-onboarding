import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/error/app_exception.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_application.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/domain/repositories/kyc_repository.dart';
import 'package:kyc_app/features/profile/presentation/cubit/profile_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../kyc/fixtures.dart';

class _MockKycRepository extends Mock implements KycRepository {}

void main() {
  late _MockKycRepository repository;
  var now = DateTime(2026, 1, 15, 10);

  final approved = KycApplication(
    status: KycStatus.approved,
    id: 'abcdef12-3456',
    details: completeDetails(),
    documentUrls: const {DocumentType.selfie: 'https://example.com/selfie'},
  );

  setUp(() {
    repository = _MockKycRepository();
    now = DateTime(2026, 1, 15, 10);
  });

  ProfileCubit build() => ProfileCubit(repository: repository, clock: () => now);

  blocTest<ProfileCubit, ProfileState>(
    'loads the verified application',
    build: () {
      when(() => repository.fetchApplication()).thenAnswer((_) async => approved);
      return build();
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      ProfileState(status: ProfileStatus.ready, application: approved, loadedAt: now),
    ],
  );

  blocTest<ProfileCubit, ProfileState>(
    'shows an error when the first load fails',
    build: () {
      when(() => repository.fetchApplication()).thenThrow(const AppException(AppErrorType.network, 'offline'));
      return build();
    },
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.status, ProfileStatus.failure);
      expect(cubit.state.errorMessage, 'offline');
    },
  );

  blocTest<ProfileCubit, ProfileState>(
    'keeps the data and reports a failed refresh',
    build: () {
      when(() => repository.fetchApplication()).thenThrow(const AppException(AppErrorType.network, 'offline'));
      return build();
    },
    seed: () => ProfileState(status: ProfileStatus.ready, application: approved, loadedAt: now),
    act: (cubit) => cubit.load(),
    verify: (cubit) {
      expect(cubit.state.status, ProfileStatus.ready);
      expect(cubit.state.application, approved);
      expect(cubit.state.message?.isError, isTrue);
    },
  );

  test('photo URLs are considered stale after 4 minutes', () {
    final cubit = build()..emit(ProfileState(status: ProfileStatus.ready, application: approved, loadedAt: now));
    expect(cubit.urlsExpired, isFalse);
    now = now.add(const Duration(minutes: 5));
    expect(cubit.urlsExpired, isTrue);
  });
}
