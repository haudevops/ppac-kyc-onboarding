import { Router } from 'express';
import type { Container } from '../container';
import { authenticate } from '../middlewares/auth.middleware';
import { createAuthRateLimiter } from '../middlewares/rate-limit.middleware';
import { validate } from '../middlewares/validate.middleware';
import { loginSchema, refreshTokenSchema, registerSchema } from '../validators/auth.schema';

export function buildAuthRouter(c: Container): Router {
  const router = Router();
  const ctrl = c.controllers.auth;
  const limiter = createAuthRateLimiter(c.env.AUTH_RATE_LIMIT_WINDOW_MS, c.env.AUTH_RATE_LIMIT_MAX);

  router.post('/register', limiter, validate({ body: registerSchema }), ctrl.register);
  router.post('/login', limiter, validate({ body: loginSchema }), ctrl.login);
  router.post('/refresh', limiter, validate({ body: refreshTokenSchema }), ctrl.refresh);
  router.post('/logout', validate({ body: refreshTokenSchema }), ctrl.logout);
  router.get('/me', authenticate(c.services.tokens), ctrl.me);

  return router;
}
