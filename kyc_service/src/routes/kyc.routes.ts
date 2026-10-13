import { Router } from 'express';
import type { Container } from '../container';
import { authenticate } from '../middlewares/auth.middleware';
import { createUploadMiddleware } from '../middlewares/upload.middleware';
import { validate } from '../middlewares/validate.middleware';
import {
  confirmUploadSchema,
  createUploadUrlSchema,
  devReviewSchema,
  documentTypeParamsSchema,
  kycDraftSchema,
} from '../validators/kyc.schema';

export function buildKycRouter(c: Container): Router {
  const router = Router();
  const ctrl = c.controllers.kyc;
  const upload = createUploadMiddleware(c.env.MAX_UPLOAD_SIZE_BYTES);
  const params = documentTypeParamsSchema;

  router.use(authenticate(c.services.tokens));
  // KYC responses contain PII and presigned URLs: never cache them anywhere.
  router.use((_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  });

  router.get('/', ctrl.getApplication);
  router.get('/status', ctrl.getStatus);
  router.put('/draft', validate({ body: kycDraftSchema }), ctrl.saveDraft);

  // Option A: upload through the API (multipart)
  router.post('/documents/:type', validate({ params }), upload.single, ctrl.uploadDocument);
  // Option B: direct-to-storage upload via presigned URL, then confirm
  router.post('/documents/:type/upload-url', validate({ params, body: createUploadUrlSchema }), ctrl.createUploadUrl);
  router.post('/documents/:type/confirm', validate({ params, body: confirmUploadSchema }), ctrl.confirmUpload);
  router.get('/documents/:type', validate({ params }), ctrl.getDocument);

  router.post('/submit', upload.submission, validate({ body: kycDraftSchema }), ctrl.submit);

  if (c.env.ENABLE_DEV_ENDPOINTS) {
    router.post('/dev/review', validate({ body: devReviewSchema }), ctrl.devReview);
  }

  return router;
}
