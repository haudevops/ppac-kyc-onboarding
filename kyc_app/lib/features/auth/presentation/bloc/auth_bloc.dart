import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/event_transformers.dart';
import '../../../../core/error/app_exception.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Called on explicit logout to wipe per-user local data (e.g. the cached KYC draft and
/// photos), so no PII stays on a shared device.
typedef UserDataCleaner = Future<void> Function(String userId);

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository, required UserDataCleaner clearUserData})
      : _repository = repository,
        _clearUserData = clearUserData,
        super(const AuthState()) {
    on<AuthSessionCheckRequested>(_onSessionCheck, transformer: droppable());
    on<AuthLoginRequested>(_onLogin, transformer: droppable());
    on<AuthRegisterRequested>(_onRegister, transformer: droppable());
    on<AuthLogoutRequested>(_onLogout, transformer: droppable());
    on<AuthSessionExpired>(_onSessionExpired);

    _expiredSubscription = _repository.sessionExpired.listen((_) => add(const AuthSessionExpired()));
  }

  final AuthRepository _repository;
  final UserDataCleaner _clearUserData;
  late final StreamSubscription<void> _expiredSubscription;

  Future<void> _onSessionCheck(AuthSessionCheckRequested event, Emitter<AuthState> emit) async {
    try {
      final result = await _repository.restoreSession();
      final user = result.user;
      emit(
        user == null
            ? const AuthState(status: AuthStatus.unauthenticated)
            : AuthState(status: AuthStatus.authenticated, user: user, isOffline: result.offline),
      );
    } on AppException catch (e) {
      emit(AuthState(status: AuthStatus.unauthenticated, errorMessage: e.message));
    }
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isSubmitting: true, errorMessage: null, sessionExpired: false));
    try {
      final user = await _repository.login(email: event.email.trim(), password: event.password);
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } on AppException catch (e) {
      emit(state.copyWith(isSubmitting: false, errorMessage: _message(e)));
    }
  }

  Future<void> _onRegister(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isSubmitting: true, errorMessage: null, sessionExpired: false));
    try {
      final user = await _repository.register(
        email: event.email.trim(),
        password: event.password,
        fullName: event.fullName?.trim(),
      );
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } on AppException catch (e) {
      emit(state.copyWith(isSubmitting: false, errorMessage: _message(e)));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    final userId = state.user?.id;
    emit(state.copyWith(isSubmitting: true));
    await _repository.logout();
    if (userId != null) {
      try {
        await _clearUserData(userId);
      } on Object {
        // Never block logout on local cleanup.
      }
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// The local KYC draft is intentionally kept: the same user logging back in resumes it.
  void _onSessionExpired(AuthSessionExpired event, Emitter<AuthState> emit) {
    if (state.status != AuthStatus.authenticated) return;
    emit(const AuthState(status: AuthStatus.unauthenticated, sessionExpired: true));
  }

  String _message(AppException e) {
    return switch (e.code) {
      'INVALID_CREDENTIALS' => 'Incorrect email or password.',
      'EMAIL_ALREADY_REGISTERED' => 'An account with this email already exists. Try logging in.',
      'TOO_MANY_REQUESTS' => 'Too many attempts. Please wait a few minutes and try again.',
      'VALIDATION_ERROR' => e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.message,
      _ => e.message,
    };
  }

  @override
  Future<void> close() async {
    await _expiredSubscription.cancel();
    return super.close();
  }
}
