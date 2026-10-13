import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../request_extras.dart';

/// Retries transient failures with exponential backoff + jitter.
///
/// Retried: connection errors, timeouts, 502/503/504 and 429.
/// Only for idempotent methods, unless the request opts in with [RequestExtras.retryable]
/// (used for KYC submit: the backend state machine makes a duplicate submit harmless,
/// it simply answers 409 KYC_NOT_EDITABLE which the bloc treats as "already submitted").
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
  }) : _dio = dio;

  final Dio _dio;
  final int maxRetries;
  final Duration baseDelay;

  static const _idempotentMethods = {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'};
  static const _retryableStatusCodes = {429, 502, 503, 504};
  final math.Random _random = math.Random();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final attempt = (request.extra[RequestExtras.retryAttempt] as int?) ?? 0;

    if (attempt >= maxRetries || !_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    await Future<void>.delayed(_backoff(attempt));
    request.extra[RequestExtras.retryAttempt] = attempt + 1;

    try {
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

  bool _shouldRetry(DioException err) {
    final request = err.requestOptions;
    if (request.cancelToken?.isCancelled ?? false) return false;

    final methodAllowed = _idempotentMethods.contains(request.method.toUpperCase()) ||
        request.extra[RequestExtras.retryable] == true;
    if (!methodAllowed) return false;

    // `default` instead of listing every value: Dio adds enum values over time
    // (e.g. transformTimeout) and an exhaustive switch would break on upgrade.
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        return _retryableStatusCodes.contains(err.response?.statusCode);
      default:
        return false;
    }
  }

  Duration _backoff(int attempt) {
    final exponential = baseDelay.inMilliseconds * math.pow(2, attempt).toInt();
    final jitter = _random.nextInt(baseDelay.inMilliseconds);
    return Duration(milliseconds: exponential + jitter);
  }
}
