import express, { Router } from 'express';
import type { FilesController } from '../controllers/files.controller';

/** Local storage driver only: signed-URL download/upload endpoints (no bearer auth - the token IS the auth). */
export function buildFilesRouter(ctrl: FilesController, maxUploadBytes: number): Router {
  const router = Router();

  router.get('/:token', ctrl.download);
  router.put('/:token', express.raw({ type: () => true, limit: maxUploadBytes }), ctrl.upload);

  return router;
}
