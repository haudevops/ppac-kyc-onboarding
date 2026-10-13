import type { Request, RequestHandler } from 'express';
import { requireUser } from '../middlewares/auth.middleware';
import { type DocumentType, SUBMIT_FILE_FIELDS } from '../models/kyc.model';
import type { KycService, UploadedFile } from '../services/kyc.service';
import { Errors } from '../utils/errors';
import { sendOk, validated } from '../utils/http';
import type {
  ConfirmUploadInput,
  CreateUploadUrlInput,
  DevReviewInput,
  DocumentTypeParams,
  KycDraftInput,
} from '../validators/kyc.schema';

export class KycController {
  constructor(private readonly kyc: KycService) {}

  /** GET /kyc - current status + full application (details, documents w/ presigned URLs, history). */
  getApplication: RequestHandler = async (req, res) => {
    sendOk(res, await this.kyc.getOverview(requireUser(req.user).id));
  };

  /** GET /kyc/status - lightweight endpoint for polling. */
  getStatus: RequestHandler = async (req, res) => {
    sendOk(res, await this.kyc.getStatus(requireUser(req.user).id));
  };

  /** PUT /kyc/draft - save partial details + wizard step (resume support). */
  saveDraft: RequestHandler = async (req, res) => {
    const application = await this.kyc.saveDraft(requireUser(req.user).id, validated<KycDraftInput>(res, 'body'));
    sendOk(res, { application });
  };

  /** POST /kyc/documents/:type (multipart, field "file"). */
  uploadDocument: RequestHandler = async (req, res) => {
    const { type } = validated<DocumentTypeParams>(res, 'params');
    if (!req.file) throw Errors.badRequest('Missing file: send multipart/form-data with a "file" field');
    const document = await this.kyc.uploadDocument(requireUser(req.user).id, type, toUploadedFile(req.file));
    sendOk(res, { document }, 201);
  };

  /** POST /kyc/documents/:type/upload-url - presigned PUT for direct-to-storage upload. */
  createUploadUrl: RequestHandler = async (req, res) => {
    const { type } = validated<DocumentTypeParams>(res, 'params');
    const upload = await this.kyc.createUploadUrl(
      requireUser(req.user).id,
      type,
      validated<CreateUploadUrlInput>(res, 'body'),
    );
    sendOk(res, { upload }, 201);
  };

  /** POST /kyc/documents/:type/confirm - attach a file uploaded via presigned URL. */
  confirmUpload: RequestHandler = async (req, res) => {
    const { type } = validated<DocumentTypeParams>(res, 'params');
    const { key } = validated<ConfirmUploadInput>(res, 'body');
    sendOk(res, { document: await this.kyc.confirmUpload(requireUser(req.user).id, type, key) });
  };

  /** GET /kyc/documents/:type - fresh short-lived view URL. */
  getDocument: RequestHandler = async (req, res) => {
    const { type } = validated<DocumentTypeParams>(res, 'params');
    sendOk(res, { document: await this.kyc.getDocument(requireUser(req.user).id, type) });
  };

  /** POST /kyc/submit - JSON or multipart (details + idFront/idBack/selfie). */
  submit: RequestHandler = async (req, res) => {
    const application = await this.kyc.submit(
      requireUser(req.user).id,
      validated<KycDraftInput>(res, 'body'),
      collectSubmissionFiles(req),
    );
    sendOk(res, { application }, 202);
  };

  /** POST /kyc/dev/review - DEV ONLY: force a decision without waiting for the worker. */
  devReview: RequestHandler = async (req, res) => {
    const application = await this.kyc.forceReview(requireUser(req.user).id, validated<DevReviewInput>(res, 'body'));
    sendOk(res, { application });
  };
}

function toUploadedFile(file: Express.Multer.File): UploadedFile {
  return { buffer: file.buffer, size: file.size };
}

function collectSubmissionFiles(req: Request): Partial<Record<DocumentType, UploadedFile>> {
  const files = req.files;
  if (!files || Array.isArray(files)) return {};

  const result: Partial<Record<DocumentType, UploadedFile>> = {};
  for (const [field, type] of Object.entries(SUBMIT_FILE_FIELDS)) {
    const file = files[field]?.[0];
    if (file) result[type] = toUploadedFile(file);
  }
  return result;
}
