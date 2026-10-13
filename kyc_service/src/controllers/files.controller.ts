import { pipeline } from 'node:stream/promises';
import type { RequestHandler } from 'express';
import type { LocalStorageProvider } from '../storage/local.storage';
import { Errors } from '../utils/errors';

/**
 * Serves the local storage driver's signed URLs (development fallback for S3/R2 presigned URLs).
 * Not mounted when STORAGE_DRIVER=s3.
 */
export class FilesController {
  constructor(
    private readonly storage: LocalStorageProvider,
    private readonly maxUploadBytes: number,
  ) {}

  /** GET /files/:token  ~ presigned GetObject */
  download: RequestHandler = async (req, res) => {
    const { key } = this.storage.verifyToken(String(req.params.token), 'get');
    const object = await this.storage.openReadStream(key);
    if (!object) throw Errors.notFound('File not found');

    res.setHeader('Content-Type', object.meta.contentType ?? 'application/octet-stream');
    res.setHeader('Content-Length', String(object.meta.contentLength));
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('Content-Disposition', 'inline');
    await pipeline(object.stream, res);
  };

  /** PUT /files/:token  ~ presigned PutObject (raw body, Content-Type must match the signed one) */
  upload: RequestHandler = async (req, res) => {
    const { key, contentType } = this.storage.verifyToken(String(req.params.token), 'put');
    const requestType = req.get('content-type')?.split(';')[0].trim().toLowerCase();

    if (!contentType || requestType !== contentType) {
      throw Errors.forbidden(`Content-Type must be "${contentType}" (it is part of the signed URL)`);
    }

    const body = req.body as unknown;
    if (!Buffer.isBuffer(body) || body.length === 0) throw Errors.badRequest('Empty upload body');
    if (body.length > this.maxUploadBytes) throw Errors.payloadTooLarge('Uploaded file is too large');

    await this.storage.putObject({ key, body, contentType });
    res.status(200).end();
  };
}
