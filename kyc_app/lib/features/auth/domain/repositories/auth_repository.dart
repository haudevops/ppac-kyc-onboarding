import '../entities/user.dart';

/// Result of restoring a session at app start.
/// `offline == true` means we could not reach the server and used the cached profile.
typedef SessionRestoreResult = ({User? user, bool offline});

abstract interface class AuthRepository {
  Future<User> login({required String email, required String password});

  Future<User> register({required String email, required String password, String? fullName});

  /// Session check on startup (validates/refreshes tokens with the backend).
  Future<SessionRestoreResult> restoreSession();

  /// Revokes the refresh token server-side (best effort) and wipes local credentials.
  Future<void> logout();

  /// Emits when the refresh token is rejected (session revoked / expired).
  Stream<void> get sessionExpired;
}
