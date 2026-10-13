part of 'auth_bloc.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

const Object _unset = Object();

final class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isSubmitting = false,
    this.isOffline = false,
    this.errorMessage,
    this.sessionExpired = false,
  });

  final AuthStatus status;
  final User? user;
  final bool isSubmitting;

  /// Authenticated from the cached profile because the backend was unreachable.
  final bool isOffline;
  final String? errorMessage;
  final bool sessionExpired;

  AuthState copyWith({
    AuthStatus? status,
    Object? user = _unset,
    bool? isSubmitting,
    bool? isOffline,
    Object? errorMessage = _unset,
    bool? sessionExpired,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: identical(user, _unset) ? this.user : user as User?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isOffline: isOffline ?? this.isOffline,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      sessionExpired: sessionExpired ?? this.sessionExpired,
    );
  }

  @override
  List<Object?> get props => [status, user, isSubmitting, isOffline, errorMessage, sessionExpired];
}
