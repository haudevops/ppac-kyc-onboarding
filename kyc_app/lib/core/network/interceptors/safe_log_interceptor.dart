import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../request_extras.dart';

/// Debug-only access log. Deliberately never prints headers or bodies:
/// they contain bearer tokens and KYC PII.
class SafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[RequestExtras.startedAt] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, '${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, '${err.response?.statusCode ?? err.type.name}');
    handler.next(err);
  }

  void _log(RequestOptions options, String outcome) {
    final started = options.extra[RequestExtras.startedAt] as int?;
    final ms = started == null ? '?' : '${DateTime.now().millisecondsSinceEpoch - started}';
    final attempt = options.extra[RequestExtras.retryAttempt];
    debugPrint('[HTTP] ${options.method} ${options.path} -> $outcome (${ms}ms)${attempt != null ? ' retry#$attempt' : ''}');
  }
}
