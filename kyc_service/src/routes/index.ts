import { Router } from 'express';
import type { Container } from '../container';
import { buildAuthRouter } from './auth.routes';
import { buildFilesRouter } from './files.routes';
import { buildKycRouter } from './kyc.routes';

/** Mounted at /api/v1 */
export function buildApiRouter(c: Container): Router {
  const router = Router();

  router.use('/auth', buildAuthRouter(c));
  router.use('/kyc', buildKycRouter(c));

  if (c.controllers.files) {
    router.use('/files', buildFilesRouter(c.controllers.files, c.env.MAX_UPLOAD_SIZE_BYTES));
  }

  return router;
}
