import type { RequestHandler } from 'express';
import multer from 'multer';
import { SUBMIT_FILE_FIELDS } from '../models/kyc.model';

/**
 * Multipart handling. Files are kept in memory (bounded by `maxFileBytes`) and validated
 * by magic bytes in the service before being streamed to object storage - nothing touches
 * the API server's disk. The client-declared MIME type is intentionally NOT used for
 * filtering (many mobile HTTP clients send application/octet-stream).
 * Non-multipart requests pass straight through (so /kyc/submit also accepts JSON).
 */
export function createUploadMiddleware(maxFileBytes: number) {
  const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: maxFileBytes,
      files: Object.keys(SUBMIT_FILE_FIELDS).length,
      fields: 30,
      fieldSize: 10 * 1024,
      parts: 40,
    },
  });

  return {
    /** Single document: multipart field `file`. */
    single: upload.single('file') as RequestHandler,
    /** Full submission: fields idFront, idBack, selfie (+ personal-details text fields). */
    submission: upload.fields(
      Object.keys(SUBMIT_FILE_FIELDS).map((name) => ({ name, maxCount: 1 })),
    ) as RequestHandler,
  };
}
