/// Keys used in `RequestOptions.extra` to configure interceptor behaviour per request.
abstract final class RequestExtras {
  /// Do not attach the bearer token / do not try to refresh on 401 (login, register, refresh, logout).
  static const skipAuth = 'kyc.skipAuth';

  /// Allow automatic retry for a non-idempotent method (only when the server makes it safe to repeat).
  static const retryable = 'kyc.retryable';

  /// `Future<FormData> Function()` used to rebuild a multipart body before a retry
  /// (a `FormData` stream can only be sent once).
  static const formDataFactory = 'kyc.formDataFactory';

  static const retryAttempt = 'kyc.retryAttempt';
  static const authRetried = 'kyc.authRetried';
  static const startedAt = 'kyc.startedAt';
}
