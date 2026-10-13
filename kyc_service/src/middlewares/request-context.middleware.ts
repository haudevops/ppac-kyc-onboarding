import type { RequestHandler } from 'express';
import type { Logger } from '../config/logger';
import { newId } from '../utils/crypto';

const VALID_REQUEST_ID = /^[A-Za-z0-9._-]{8,128}$/;

/** Assigns/propagates X-Request-Id so client errors can be correlated with server logs. */
export const requestId: RequestHandler = (req, res, next) => {
  const incoming = req.get('x-request-id');
  req.requestId = incoming && VALID_REQUEST_ID.test(incoming) ? incoming : newId();
  res.setHeader('X-Request-Id', req.requestId);
  next();
};

/**
 * Access log. Logs the path only (never the query string or body): local presigned
 * file URLs carry signed tokens, and bodies contain PII.
 */
export const requestLogger =
  (logger: Logger): RequestHandler =>
  (req, res, next) => {
    const start = process.hrtime.bigint();
    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
      const path = req.originalUrl.split('?')[0];
      logger.info('http', {
        requestId: req.requestId,
        method: req.method,
        path: path.startsWith('/api/v1/files/') ? '/api/v1/files/:token' : path,
        status: res.statusCode,
        durationMs: Math.round(durationMs),
      });
    });
    next();
  };
