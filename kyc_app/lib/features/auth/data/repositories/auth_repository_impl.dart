import 'dart:convert';

import '../../../../core/error/app_exception.dart';
import '../../../../core/network/session_events.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_models.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
  })  : _remote = remote,
        _tokens = tokenStorage,
        _sessionEvents = sessionEvents;

  final AuthRemoteDataSource _remote;
  final TokenStorage _tokens;
  final SessionEvents _sessionEvents;

  @override
  Stream<void> get sessionExpired => _sessionEvents.onSessionExpired;

  @override
  Future<User> login({required String email, required String password}) async {
    return _persist(await _remote.login(email: email, password: password));
  }

  @override
  Future<User> register({required String email, required String password, String? fullName}) async {
    return _persist(await _remote.register(email: email, password: password, fullName: fullName));
  }

  @override
  Future<SessionRestoreResult> restoreSession() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) return (user: null, offline: false);

    try {
      // An expired access token is refreshed transparently by the AuthInterceptor.
      final user = await _remote.me();
      await _tokens.saveUserJson(jsonEncode(userToJson(user)));
      return (user: user, offline: false);
    } on AppException catch (e) {
      if (e.isConnectivity || e.type == AppErrorType.server) {
        // Can't reach the backend: let the user continue (and resume their draft) offline.
        final cached = await _cachedUser();
        if (cached != null) return (user: cached, offline: true);
        rethrow;
      }
      await _tokens.clear();
      return (user: null, offline: false);
    }
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _tokens.readRefreshToken();
    try {
      if (refreshToken != null) await _remote.logout(refreshToken);
    } on AppException {
      // Best effort: local logout must always succeed, even offline.
    } finally {
      await _tokens.clear();
    }
  }

  Future<User> _persist(AuthSession session) async {
    await _tokens.saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
    await _tokens.saveUserJson(jsonEncode(userToJson(session.user)));
    return session.user;
  }

  Future<User?> _cachedUser() async {
    final raw = await _tokens.readUserJson();
    if (raw == null) return null;
    try {
      return userFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }
}
