import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../error/app_exception.dart';
import '../storage/token_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/safe_log_interceptor.dart';
import 'request_extras.dart';
import 'session_events.dart';

typedef FormDataBuilder = Future<FormData> Function();

/// Thin wrapper over Dio:
///  * unwraps the backend envelope `{ success, data }` and returns `data`;
///  * converts every failure into an [AppException];
///  * exposes per-request switches for auth / retry;
///  * multipart uploads take a *builder* so the body can be recreated on retry.
class ApiClient {
  ApiClient(this._dio);

  factory ApiClient.create({
    required AppConfig config,
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
  }) {
    BaseOptions baseOptions() => BaseOptions(
          baseUrl: config.apiUrl,
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          sendTimeout: config.sendTimeout,
          headers: {'Accept': 'application/json'},
        );

    final dio = Dio(baseOptions());
    final refreshDio = Dio(baseOptions());

    // onError runs in insertion order: auth (401 -> refresh) first, then retry (transient errors).
    dio.interceptors.addAll([
      AuthInterceptor(
        dio: dio,
        refreshDio: refreshDio,
        tokenStorage: tokenStorage,
        sessionEvents: sessionEvents,
      ),
      RetryInterceptor(dio: dio, maxRetries: config.maxRetries),
      if (kDebugMode) SafeLogInterceptor(),
    ]);
    // refreshDio intentionally has no retry: replaying a rotated refresh token would be
    // detected as token reuse by the backend.
    if (kDebugMode) refreshDio.interceptors.add(SafeLogInterceptor());

    return ApiClient(dio);
  }

  final Dio _dio;

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) {
    return _send(() => _dio.get<dynamic>(path, options: _options(authenticated: authenticated)));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    bool authenticated = true,
    bool retryable = false,
    Duration? timeout,
  }) {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: _options(authenticated: authenticated, retryable: retryable, timeout: timeout),
      ),
    );
  }

  Future<Map<String, dynamic>> put(String path, {Object? data, bool authenticated = true}) {
    return _send(() => _dio.put<dynamic>(path, data: data, options: _options(authenticated: authenticated)));
  }

  /// Multipart POST. [buildForm] is invoked for the first attempt and again for every retry.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required FormDataBuilder buildForm,
    ProgressCallback? onSendProgress,
    bool retryable = true,
  }) async {
    final form = await buildForm();
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: form,
        onSendProgress: onSendProgress,
        options: _options(
          retryable: retryable,
          extra: {RequestExtras.formDataFactory: buildForm},
        ),
      ),
    );
  }

  Options _options({
    bool authenticated = true,
    bool retryable = false,
    Duration? timeout,
    Map<String, Object?> extra = const {},
  }) {
    return Options(
      sendTimeout: timeout,
      receiveTimeout: timeout,
      extra: {
        RequestExtras.skipAuth: !authenticated,
        RequestExtras.retryable: retryable,
        ...extra,
      },
    );
  }

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return data;
      }
      return <String, dynamic>{}; // e.g. 204 No Content
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}
