part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// App start: is there a valid session?
final class AuthSessionCheckRequested extends AuthEvent {
  const AuthSessionCheckRequested();
}

final class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email];
}

final class AuthRegisterRequested extends AuthEvent {
  const AuthRegisterRequested({required this.email, required this.password, this.fullName});

  final String email;
  final String password;
  final String? fullName;

  @override
  List<Object?> get props => [email, fullName];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Raised by the network layer when the refresh token is rejected.
final class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}
