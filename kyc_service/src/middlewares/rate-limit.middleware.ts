import { rateLimit } from 'express-rate-limit';
import { Errors } from '../utils/errors';

/** Brute-force protection for credential endpoints (per IP). */
export const createAuthRateLimiter = (windowMs: number, limit: number) =>
  rateLimit({
    windowMs,
    limit,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: (_req, _res, next) => next(Errors.tooManyRequests('Too many authentication attempts, try again later')),
  });
