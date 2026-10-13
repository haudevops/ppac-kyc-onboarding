import { Prisma } from '@prisma/client';
import type { ErrorRequestHandler, RequestHandler } from 'express';
import multer from 'multer';
import { ZodError } from 'zod';
import type { Logger } from '../config/logger';
import { AppError, Errors } from '../utils/errors';
import { formatZodIssues } from '../utils/zod';

export const notFoundHandler: RequestHandler = (req, _res, next) => {
  next(Errors.notFound(`Route ${req.method} ${req.baseUrl}${req.path} not found`));
};

/**
 * Single place that turns any thrown error into the API error envelope:
 *   { success: false, error: { code, message, details? }, requestId }
 * Unknown errors become a generic 500 - internals are logged, never returned.
 */
export const errorHandler =
  (logger: Logger, exposeInternalErrors: boolean): ErrorRequestHandler =>
  (err, req, res, next) => {
    const appError = toAppError(err, exposeInternalErrors);

    if (appError.statusCode >= 500) {
      logger.error('Request failed', {
        requestId: req.requestId,
        code: appError.code,
        err: err instanceof Error ? err : new Error(String(err)),
        cause: appError.cause instanceof Error ? appError.cause : undefined,
      });
    }

    if (res.headersSent) return next(err);

    if (appError.statusCode === 401) res.setHeader('WWW-Authenticate', 'Bearer');
    res.status(appError.statusCode).json({
      success: false,
      error: {
        code: appError.code,
        message: appError.message,
        ...(appError.details !== undefined ? { details: appError.details } : {}),
      },
      requestId: req.requestId,
    });
  };

function toAppError(err: unknown, exposeInternalErrors: boolean): AppError {
  if (err instanceof AppError) return err;

  if (err instanceof ZodError) return Errors.validation(formatZodIssues(err));

  if (err instanceof multer.MulterError) {
    switch (err.code) {
      case 'LIMIT_FILE_SIZE':
        return Errors.payloadTooLarge('Uploaded file is too large');
      case 'LIMIT_UNEXPECTED_FILE':
        return Errors.badRequest(`Unexpected file field "${err.field ?? ''}"`);
      default:
        return Errors.badRequest(`Invalid multipart request: ${err.message}`);
    }
  }

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') return Errors.conflict('Resource already exists');
    if (err.code === 'P2025') return Errors.notFound();
  }

  // Errors raised by body-parser / raw-body (malformed JSON, payload too large, ...)
  const httpErr = err as { type?: string; status?: number; statusCode?: number; message?: string };
  if (httpErr?.type === 'entity.parse.failed') return Errors.badRequest('Malformed JSON body');
  if (httpErr?.type === 'entity.too.large') return Errors.payloadTooLarge('Request body is too large');
  const status = httpErr?.status ?? httpErr?.statusCode;
  if (typeof status === 'number' && status >= 400 && status < 500) {
    return new AppError(status, 'BAD_REQUEST', httpErr.message ?? 'Bad request');
  }

  const message = exposeInternalErrors && err instanceof Error ? err.message : 'Internal server error';
  return Errors.internal(message, err);
}
