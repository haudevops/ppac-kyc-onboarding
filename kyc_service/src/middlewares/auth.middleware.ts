import type { RequestHandler } from 'express';
import type { TokenService } from '../services/token.service';
import { Errors } from '../utils/errors';

/** Requires a valid `Authorization: Bearer <accessToken>` header and sets `req.user`. */
export const authenticate =
  (tokens: TokenService): RequestHandler =>
  (req, _res, next) => {
    const header = req.get('authorization');
    const [scheme, token] = header?.split(' ') ?? [];

    if (scheme?.toLowerCase() !== 'bearer' || !token) {
      return next(Errors.unauthorized('Missing or malformed Authorization header (expected "Bearer <token>")'));
    }

    req.user = tokens.verifyAccessToken(token.trim());
    next();
  };

/** Narrows `req.user` inside handlers mounted behind `authenticate`. */
export function requireUser(user: Express.Request['user']) {
  if (!user) throw Errors.unauthorized();
  return user;
}
