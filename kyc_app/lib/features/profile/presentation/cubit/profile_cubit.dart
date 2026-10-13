import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/presentation/ui_message.dart';
import '../../../kyc/domain/entities/kyc_application.dart';
import '../../../kyc/domain/repositories/kyc_repository.dart';

enum ProfileStatus { loading, ready, failure }

const Object _unset = Object();

final class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.loading,
    this.application,
    this.isRefreshing = false,
    this.loadedAt,
    this.message,
    this.errorMessage,
  });

  final ProfileStatus status;

  /// Verified data as stored on the server (the local draft is wiped after approval).
  final KycApplication? application;
  final bool isRefreshing;

  /// When the presigned image URLs were issued (they expire after a few minutes).
  final DateTime? loadedAt;
  final UiMessage? message;
  final String? errorMessage;

  ProfileState copyWith({
    ProfileStatus? status,
    Object? application = _unset,
    bool? isRefreshing,
    Object? loadedAt = _unset,
    Object? message = _unset,
    Object? errorMessage = _unset,
  }) {
    return ProfileState(
      status: status ?? this.status,
      application: identical(application, _unset) ? this.application : application as KycApplication?,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      loadedAt: identical(loadedAt, _unset) ? this.loadedAt : loadedAt as DateTime?,
      message: identical(message, _unset) ? this.message : message as UiMessage?,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [status, application, isRefreshing, loadedAt, message, errorMessage];
}

/// Loads the verified profile from GET /kyc (details + fresh presigned photo URLs).
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({required KycRepository repository, DateTime Function()? clock})
      : _repository = repository,
        _now = clock ?? DateTime.now,
        super(const ProfileState());

  final KycRepository _repository;
  final DateTime Function() _now;

  /// Presigned URLs live 5 minutes on the backend; refresh a bit earlier.
  static const urlLifetime = Duration(minutes: 4);

  bool get urlsExpired {
    final loadedAt = state.loadedAt;
    return loadedAt == null || _now().difference(loadedAt) > urlLifetime;
  }

  Future<void> load() async {
    final hasData = state.application != null;
    emit(hasData
        ? state.copyWith(isRefreshing: true)
        : const ProfileState(status: ProfileStatus.loading));

    try {
      final application = await _repository.fetchApplication();
      if (application == null) {
        emit(const ProfileState(status: ProfileStatus.failure, errorMessage: 'No verified profile was found.'));
        return;
      }
      emit(ProfileState(status: ProfileStatus.ready, application: application, loadedAt: _now()));
    } on AppException catch (e) {
      emit(hasData
          // Keep showing what we have; just report the failed refresh.
          ? state.copyWith(isRefreshing: false, message: UiMessage.error(e.message))
          : ProfileState(status: ProfileStatus.failure, errorMessage: e.message));
    }
  }

  /// Re-fetches only when the photo URLs are about to expire (e.g. app resumed after a while).
  Future<void> refreshIfStale() async {
    if (state.status == ProfileStatus.ready && !state.isRefreshing && urlsExpired) await load();
  }
}
