import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';
import '../request_extras.dart';
import '../session_events.dart';

/// Attaches the access token and transparently refreshes it on 401.
///
/// * Single-flight refresh: concurrent 401s share one `/auth/refresh` call (the backend rotates
///   refresh tokens and treats reuse as theft, so two parallel refreshes would log the user out).
/// * The original request is replayed once with the new token.
/// * If the refresh token is rejected, tokens are cleared and [SessionEvents] notifies the app.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required Dio refreshDio,
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
  })  : _dio = dio,
        _refreshDio = refreshDio,
        _tokens = tokenStorage,
        _sessionEvents = sessionEvents;

  final Dio _dio;

  /// Bare Dio without this interceptor, so refreshing can never recurse.
  final Dio _refreshDio;
  final TokenStorage _tokens;
  final SessionEvents _sessionEvents;

  Future<String?>? _refreshInFlight;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[RequestExtras.skipAuth] != true) {
      final token = await _tokens.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final shouldRefresh = err.response?.statusCode == 401 &&
        request.extra[RequestExtras.skipAuth] != true &&
        request.extra[RequestExtras.authRetried] != true;

    if (!shouldRefresh) {
      handler.next(err);
      return;
    }

    try {
      final newToken = await _refreshAccessToken();
      if (newToken == null) {
        _sessionEvents.notifyExpired();
        handler.next(err);
        return;
      }

      request.extra[RequestExtras.authRetried] = true;
      request.headers['Authorization'] = 'Bearer $newToken';
      final factory = request.extra[RequestExtras.formDataFactory];
      if (factory is Future<FormData> Function()) request.data = await factory();

      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
      return;
    } on DioException catch (e) {
      handler.next(e);
      return;
    }
  }

  Future<String?> _refreshAccessToken() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final tokens = (response.data?['data'] as Map<String, dynamic>?)?['tokens'] as Map<String, dynamic>?;
      final access = tokens?['accessToken'] as String?;
      final refresh = tokens?['refreshToken'] as String?;
      if (access == null || refresh == null) return null;

      await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        // Refresh token expired, revoked or reused: the session is over.
        await _tokens.clear();
        return null;
      }
      // Connectivity problem: keep the tokens and surface the original error.
      rethrow;
    }
  }
}
