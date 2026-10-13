/**
 * Application error model. Every error that reaches the client is an AppError with a stable,
 * machine-readable `code` the mobile app can switch on, plus a human-readable message.
 */
export type ErrorCode =
  | 'BAD_REQUEST'
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'INVALID_CREDENTIALS'
  | 'INVALID_TOKEN'
  | 'TOKEN_EXPIRED'
  | 'INVALID_REFRESH_TOKEN'
  | 'REFRESH_TOKEN_REUSED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'EMAIL_ALREADY_REGISTERED'
  | 'KYC_NOT_FOUND'
  | 'KYC_NOT_EDITABLE'
  | 'KYC_INVALID_TRANSITION'
  | 'KYC_INCOMPLETE'
  | 'PAYLOAD_TOO_LARGE'
  | 'UNSUPPORTED_MEDIA_TYPE'
  | 'TOO_MANY_REQUESTS'
  | 'STORAGE_ERROR'
  | 'INTERNAL_ERROR';

export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: ErrorCode,
    message: string,
    public readonly details?: unknown,
    options?: { cause?: unknown },
  ) {
    super(message, options);
    this.name = 'AppError';
  }
}

export const Errors = {
  badRequest: (message: string, details?: unknown) => new AppError(400, 'BAD_REQUEST', message, details),
  validation: (details: unknown, message = 'Request validation failed') =>
    new AppError(400, 'VALIDATION_ERROR', message, details),
  unauthorized: (message = 'Authentication required', code: ErrorCode = 'UNAUTHORIZED') =>
    new AppError(401, code, message),
  forbidden: (message = 'You do not have access to this resource', code: ErrorCode = 'FORBIDDEN') =>
    new AppError(403, code, message),
  notFound: (message = 'Resource not found', code: ErrorCode = 'NOT_FOUND') => new AppError(404, code, message),
  conflict: (message: string, code: ErrorCode = 'CONFLICT', details?: unknown) =>
    new AppError(409, code, message, details),
  unprocessable: (message: string, code: ErrorCode, details?: unknown) => new AppError(422, code, message, details),
  payloadTooLarge: (message: string) => new AppError(413, 'PAYLOAD_TOO_LARGE', message),
  unsupportedMediaType: (message: string) => new AppError(415, 'UNSUPPORTED_MEDIA_TYPE', message),
  tooManyRequests: (message = 'Too many requests, please try again later') =>
    new AppError(429, 'TOO_MANY_REQUESTS', message),
  storage: (message: string, cause?: unknown) => new AppError(502, 'STORAGE_ERROR', message, undefined, { cause }),
  internal: (message = 'Internal server error', cause?: unknown) =>
    new AppError(500, 'INTERNAL_ERROR', message, undefined, { cause }),
};
