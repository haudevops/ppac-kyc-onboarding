import 'dart:io';

import 'package:dio/dio.dart';

enum AppErrorType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  server,
  cancelled,
  storage,
  unknown,
}

/// The single error type that crosses layer boundaries (data -> domain -> presentation).
///
/// Mirrors the backend envelope `{ error: { code, message, details }, requestId }` so the
/// UI can react to stable machine-readable codes (e.g. `KYC_INCOMPLETE`).
class AppException implements Exception {
  const AppException(
    this.type,
    this.message, {
    this.code,
    this.statusCode,
    this.details,
    this.requestId,
  });

  factory AppException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const AppException(
          AppErrorType.timeout,
          'The server is taking too long to respond. Please try again.',
        );
      case DioExceptionType.connectionError:
        return const AppException(
          AppErrorType.network,
          'No internet connection. Your progress is saved on this device.',
        );
      case DioExceptionType.badCertificate:
        return const AppException(AppErrorType.network, 'Could not establish a secure connection.');
      case DioExceptionType.cancel:
        return const AppException(AppErrorType.cancelled, 'Request cancelled.');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.unknown:
        if (e.error is SocketException) {
          return const AppException(
            AppErrorType.network,
            'No internet connection. Your progress is saved on this device.',
          );
        }
        return const AppException(AppErrorType.unknown, 'Something went wrong. Please try again.');
      // Values added in future Dio versions.
      // ignore: unreachable_switch_default
      default:
        return const AppException(AppErrorType.unknown, 'Something went wrong. Please try again.');
    }
  }

  static AppException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    String? code;
    String? message;
    Object? details;
    String? requestId;

    final body = response?.data;
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        code = error['code'] as String?;
        message = error['message'] as String?;
        details = error['details'];
      }
      requestId = body['requestId'] as String?;
    }

    final type = switch (status) {
      400 || 422 => AppErrorType.validation,
      401 => AppErrorType.unauthorized,
      403 => AppErrorType.forbidden,
      404 => AppErrorType.notFound,
      409 => AppErrorType.conflict,
      >= 500 => AppErrorType.server,
      _ => AppErrorType.unknown,
    };

    return AppException(
      type,
      message ?? (type == AppErrorType.server ? 'Server error. Please try again later.' : 'Request failed ($status).'),
      code: code,
      statusCode: status,
      details: details,
      requestId: requestId,
    );
  }

  final AppErrorType type;
  final String message;

  /// Backend error code, e.g. `VALIDATION_ERROR`, `KYC_INCOMPLETE`, `KYC_NOT_EDITABLE`.
  final String? code;
  final int? statusCode;
  final Object? details;
  final String? requestId;

  bool get isConnectivity => type == AppErrorType.network || type == AppErrorType.timeout;

  /// Field -> message, from either `VALIDATION_ERROR` (list of issues) or
  /// `KYC_INCOMPLETE` (`details.fieldIssues`). Keys use the API field names.
  Map<String, String> get fieldErrors {
    final issues = switch (details) {
      final List<dynamic> list => list,
      final Map<dynamic, dynamic> map when map['fieldIssues'] is List => map['fieldIssues'] as List<dynamic>,
      _ => const <dynamic>[],
    };
    final result = <String, String>{};
    for (final issue in issues) {
      if (issue is! Map) continue;
      final field = issue['field'];
      final message = issue['message'];
      if (field is String && message is String) {
        final key = field.startsWith('body.') ? field.substring(5) : field;
        result.putIfAbsent(key, () => message);
      }
    }
    return result;
  }

  /// Document types (API values) reported missing by `KYC_INCOMPLETE`.
  List<String> get missingDocuments {
    final d = details;
    if (d is Map && d['missingDocuments'] is List) {
      return (d['missingDocuments'] as List<dynamic>).whereType<String>().toList();
    }
    return const [];
  }

  @override
  String toString() => 'AppException($type, $code, $statusCode): $message';
}
