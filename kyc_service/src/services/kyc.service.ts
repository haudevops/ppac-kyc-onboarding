import { Prisma, type KycDocument } from '@prisma/client';
import type { Logger } from '../config/logger';
import {
  DOCUMENT_TYPES,
  type DocumentType,
  type KycAction,
  type KycApplicationWithRelations,
  type KycStatus,
  NOT_STARTED,
  PERSONAL_DETAIL_FIELDS,
  type PersonalDetailsRecord,
  type ResubmissionItem,
  USER_EDITABLE_STATUSES,
  allowedActionsFor,
  extractPersonalDetails,
  maskIdentifier,
  parseResubmissionItems,
  requiredDocumentsFor,
  toKycStatus,
} from '../models/kyc.model';
import type { DocumentInput, KycRepository } from '../repositories/kyc.repository';
import type { PresignedUpload, StorageProvider } from '../storage/storage.provider';
import { type ReviewDecision, decisionUpdate } from './kyc-reviewer.service';
import { newId, sha256Hex } from '../utils/crypto';
import { AppError, Errors } from '../utils/errors';
import { type AllowedImageType, IMAGE_EXTENSIONS, IMAGE_SIGNATURE_BYTES, detectImageType } from '../utils/image';
import { type FieldIssue, formatZodIssues } from '../utils/zod';
import {
  type CreateUploadUrlInput,
  type DevReviewInput,
  type KycDraftInput,
  crossFieldIssues,
  personalDetailsSchema,
} from '../validators/kyc.schema';

/* ------------------------------------------------------------------ */
/* Public types (response DTOs)                                       */
/* ------------------------------------------------------------------ */

export interface UploadedFile {
  buffer: Buffer;
  size: number;
}

export interface KycServiceConfig {
  keyPrefix: string;
  downloadTtlSeconds: number;
  uploadTtlSeconds: number;
  maxUploadBytes: number;
}

export interface KycCompleteness {
  isComplete: boolean;
  requiredDocuments: DocumentType[];
  missingDocuments: DocumentType[];
  /** Required fields that are missing or currently invalid (e.g. an ID that expired since the draft was saved). */
  fieldIssues: FieldIssue[];
}

export interface KycDocumentView {
  type: DocumentType;
  contentType: string;
  sizeBytes: number;
  uploadedAt: Date;
  /** Short-lived presigned URL - never cache it. */
  url: string;
  urlExpiresAt: Date;
}

export interface KycHistoryView {
  fromStatus: string | null;
  toStatus: string;
  actor: string;
  reason: string | null;
  at: Date;
}

export interface KycApplicationView {
  id: string;
  status: KycStatus;
  version: number;
  currentStep: string | null;
  personalDetails: PersonalDetailsRecord;
  documents: KycDocumentView[];
  completeness: KycCompleteness | null;
  allowedActions: KycAction[];
  submittedAt: Date | null;
  processingStartedAt: Date | null;
  reviewedAt: Date | null;
  /** Reviewer message for REJECTED / RESUBMISSION_REQUESTED (kept until the next submit). */
  rejectionReason: string | null;
  /** What the reviewer asked the user to redo (RESUBMISSION_REQUESTED). */
  resubmissionItems: ResubmissionItem[];
  history: KycHistoryView[];
  createdAt: Date;
  updatedAt: Date;
}

export interface KycOverview {
  status: KycStatus | typeof NOT_STARTED;
  allowedActions: KycAction[];
  application: KycApplicationView | null;
}

export interface KycStatusView {
  status: KycStatus | typeof NOT_STARTED;
  allowedActions: KycAction[];
  version: number | null;
  rejectionReason: string | null;
  resubmissionItems: ResubmissionItem[];
  submittedAt: Date | null;
  reviewedAt: Date | null;
  updatedAt: Date | null;
}

export interface DocumentUploadTicket extends PresignedUpload {
  documentType: DocumentType;
  key: string;
  maxSizeBytes: number;
}

/* ------------------------------------------------------------------ */
/* Service                                                            */
/* ------------------------------------------------------------------ */

export class KycService {
  constructor(
    private readonly repo: KycRepository,
    private readonly storage: StorageProvider,
    private readonly logger: Logger,
    private readonly config: KycServiceConfig,
  ) {}

  /* ----------------------------- Queries ---------------------------- */

  async getOverview(userId: string): Promise<KycOverview> {
    const app = await this.repo.findByUserId(userId);
    if (!app) return { status: NOT_STARTED, allowedActions: allowedActionsFor(NOT_STARTED), application: null };
    const view = await this.toView(app);
    return { status: view.status, allowedActions: view.allowedActions, application: view };
  }

  /** Lightweight status for polling (no DB joins, no URL signing). */
  async getStatus(userId: string): Promise<KycStatusView> {
    const snapshot = await this.repo.findStatusByUserId(userId);
    if (!snapshot) {
      return {
        status: NOT_STARTED,
        allowedActions: allowedActionsFor(NOT_STARTED),
        version: null,
        rejectionReason: null,
        resubmissionItems: [],
        submittedAt: null,
        reviewedAt: null,
        updatedAt: null,
      };
    }
    const status = toKycStatus(snapshot.status);
    return {
      ...snapshot,
      status,
      resubmissionItems: parseResubmissionItems(snapshot.resubmissionItems),
      allowedActions: allowedActionsFor(status),
    };
  }

  async getDocument(userId: string, type: DocumentType): Promise<KycDocumentView> {
    const app = await this.repo.findByUserId(userId);
    if (!app) throw Errors.notFound('No KYC application found', 'KYC_NOT_FOUND');
    return this.findDocumentView(app, type);
  }

  /* ---------------------------- Commands ---------------------------- */

  /** Saves (partial) personal details and the client's wizard step so an interrupted flow can resume. */
  async saveDraft(userId: string, input: KycDraftInput): Promise<KycApplicationView> {
    const app = await this.getEditableApplication(userId);
    const updated = await this.repo.updateFields(app.id, ['DRAFT'], toUpdateData(input));
    if (!updated) throw await this.notEditableError(app.id);
    return this.toView(await this.reload(app.id));
  }

  /** Multipart upload through the API (server -> storage). */
  async uploadDocument(userId: string, type: DocumentType, file: UploadedFile): Promise<KycDocumentView> {
    const contentType = this.assertSupportedImage(file, type);
    const app = await this.getEditableApplication(userId);
    await this.storeDocument(app.id, userId, type, file.buffer, contentType);
    return this.findDocumentView(await this.reload(app.id), type);
  }

  /** Step 1 of a direct-to-storage upload: returns a presigned PUT URL (the file never transits the API). */
  async createUploadUrl(userId: string, type: DocumentType, input: CreateUploadUrlInput): Promise<DocumentUploadTicket> {
    const app = await this.getEditableApplication(userId);
    const key = this.buildObjectKey(userId, app.id, type, input.contentType);
    const presigned = await this.storage.createPresignedUploadUrl({
      key,
      contentType: input.contentType,
      ttlSeconds: this.config.uploadTtlSeconds,
    });
    return { ...presigned, documentType: type, key, maxSizeBytes: this.config.maxUploadBytes };
  }

  /** Step 2 of a direct upload: verifies the object (ownership, size, real file type) and attaches it. */
  async confirmUpload(userId: string, type: DocumentType, key: string): Promise<KycDocumentView> {
    const app = await this.getEditableApplication(userId);

    if (!key.startsWith(this.objectKeyPrefix(userId, app.id, type))) {
      throw Errors.forbidden('This upload key does not belong to your application or document type');
    }

    const meta = await this.storage.getObjectMetadata(key);
    if (!meta) throw Errors.notFound('Uploaded file not found. PUT the file to the upload URL before confirming.');

    if (meta.contentLength <= 0 || meta.contentLength > this.config.maxUploadBytes) {
      await this.safeDelete(key);
      throw Errors.payloadTooLarge(`File must be between 1 byte and ${this.config.maxUploadBytes} bytes`);
    }

    const detected = detectImageType(await this.storage.readObjectPrefix(key, IMAGE_SIGNATURE_BYTES));
    if (!detected || (meta.contentType && meta.contentType !== detected)) {
      await this.safeDelete(key);
      throw Errors.unsupportedMediaType('File content is not a valid JPEG, PNG or WEBP image matching its Content-Type');
    }

    await this.attachDocument(app.id, { type, storageKey: key, contentType: detected, sizeBytes: meta.contentLength });
    return this.findDocumentView(await this.reload(app.id), type);
  }

  /**
   * Submits the application. Accepts any combination of:
   *  - personal-details fields in the body (merged over the saved draft), and
   *  - image files (idFront / idBack / selfie) - images uploaded earlier are reused.
   * Everything provided is persisted first, so if the application is still incomplete the user
   * gets a 422 listing what is missing and does not lose their progress.
   */
  async submit(
    userId: string,
    input: KycDraftInput,
    files: Partial<Record<DocumentType, UploadedFile>>,
  ): Promise<KycApplicationView> {
    // Validate every file before storing any, so a bad file doesn't leave a half-applied request.
    const validatedFiles = (Object.entries(files) as [DocumentType, UploadedFile][]).map(([type, file]) => ({
      type,
      file,
      contentType: this.assertSupportedImage(file, type),
    }));

    const app = await this.getEditableApplication(userId);

    for (const { type, file, contentType } of validatedFiles) {
      await this.storeDocument(app.id, userId, type, file.buffer, contentType);
    }

    const data = toUpdateData(input);
    if (Object.keys(data).length > 0 && !(await this.repo.updateFields(app.id, ['DRAFT'], data))) {
      throw await this.notEditableError(app.id);
    }

    const completeness = this.evaluateCompleteness(await this.reload(app.id));
    if (!completeness.isComplete) {
      throw Errors.unprocessable(
        'KYC application is incomplete. Your progress has been saved as a draft.',
        'KYC_INCOMPLETE',
        completeness,
      );
    }

    const submitted = await this.repo.transition({
      id: app.id,
      from: ['DRAFT'],
      to: 'SUBMITTED',
      actor: 'USER',
      reason: 'Submitted for review',
      data: {
        submittedAt: new Date(),
        processingStartedAt: null,
        reviewedAt: null,
        rejectionReason: null,
        resubmissionItems: null,
      },
    });
    if (!submitted) throw await this.notEditableError(app.id);

    this.logger.info('KYC application submitted', { applicationId: app.id });
    return this.toView(await this.reload(app.id));
  }

  /** DEV ONLY - immediately decide (approve / reject / request resubmission) a SUBMITTED or PROCESSING application. */
  async forceReview(userId: string, input: DevReviewInput): Promise<KycApplicationView> {
    const app = await this.repo.findByUserId(userId);
    if (!app) throw Errors.notFound('No KYC application found', 'KYC_NOT_FOUND');

    const status = toKycStatus(app.status);
    if (status !== 'SUBMITTED' && status !== 'PROCESSING') {
      throw Errors.conflict(
        `Only SUBMITTED or PROCESSING applications can be reviewed (current: ${status})`,
        'KYC_INVALID_TRANSITION',
      );
    }

    if (status === 'SUBMITTED') {
      await this.repo.transition({
        id: app.id,
        from: ['SUBMITTED'],
        to: 'PROCESSING',
        actor: 'SYSTEM',
        reason: 'Picked up by manual review (dev endpoint)',
        data: { processingStartedAt: new Date() },
      });
    }

    const defaultReason: Record<ReviewDecision['decision'], string> = {
      APPROVED: 'Approved by manual review',
      REJECTED: 'Rejected by manual review',
      RESUBMISSION_REQUESTED: 'Please redo the requested items',
    };
    const decision: ReviewDecision = {
      decision: input.decision,
      reason: input.reason ?? defaultReason[input.decision],
      items: input.decision === 'RESUBMISSION_REQUESTED' ? (input.items ?? ['SELFIE']) : undefined,
    };
    const reviewed = await this.repo.transition({
      id: app.id,
      from: ['PROCESSING'],
      to: decision.decision,
      actor: 'SYSTEM',
      reason: decision.reason,
      data: decisionUpdate(decision),
    });
    if (!reviewed) throw Errors.conflict('Application status changed concurrently, please retry', 'KYC_INVALID_TRANSITION');

    return this.toView(await this.reload(app.id));
  }

  /* ---------------------------- Internals --------------------------- */

  /**
   * Returns the user's application in DRAFT, creating it if needed.
   * When the reviewer requested a resubmission, the application is re-opened
   * (RESUBMISSION_REQUESTED -> DRAFT) and the requested photos are discarded, so they must be
   * retaken before the next submit. The reviewer's message and items are kept until then.
   * REJECTED and APPROVED are final.
   */
  private async getEditableApplication(userId: string): Promise<KycApplicationWithRelations> {
    const app = (await this.repo.findByUserId(userId)) ?? (await this.createDraft(userId));
    const status = toKycStatus(app.status);

    if (status === 'DRAFT') return app;

    if (status === 'RESUBMISSION_REQUESTED') {
      const reopenedNow = await this.repo.transition({
        id: app.id,
        from: ['RESUBMISSION_REQUESTED'],
        to: 'DRAFT',
        actor: 'USER',
        reason: 'Re-opened for resubmission',
        data: { submittedAt: null, processingStartedAt: null, reviewedAt: null },
      });
      if (reopenedNow) {
        const requestedDocuments = parseResubmissionItems(app.resubmissionItems).filter(
          (item): item is DocumentType => (DOCUMENT_TYPES as readonly string[]).includes(item),
        );
        const keys = await this.repo.deleteDocuments(app.id, requestedDocuments);
        await Promise.all(keys.map((key) => this.safeDelete(key)));
      }
      const reopened = await this.reload(app.id);
      if (reopened.status !== 'DRAFT') throw this.notEditable(toKycStatus(reopened.status));
      return reopened;
    }

    throw this.notEditable(status);
  }

  private async createDraft(userId: string): Promise<KycApplicationWithRelations> {
    try {
      return await this.repo.createDraft(userId);
    } catch (err) {
      // Two concurrent first requests: the other one created it.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        const existing = await this.repo.findByUserId(userId);
        if (existing) return existing;
      }
      throw err;
    }
  }

  private async reload(applicationId: string): Promise<KycApplicationWithRelations> {
    const app = await this.repo.findById(applicationId);
    if (!app) throw Errors.notFound('No KYC application found', 'KYC_NOT_FOUND');
    return app;
  }

  private async storeDocument(
    applicationId: string,
    userId: string,
    type: DocumentType,
    body: Buffer,
    contentType: AllowedImageType,
  ): Promise<void> {
    const key = this.buildObjectKey(userId, applicationId, type, contentType);
    await this.storage.putObject({ key, body, contentType });
    await this.attachDocument(applicationId, {
      type,
      storageKey: key,
      contentType,
      sizeBytes: body.length,
      sha256: sha256Hex(body),
    });
  }

  private async attachDocument(applicationId: string, doc: DocumentInput): Promise<void> {
    const result = await this.repo.upsertDocument(applicationId, ['DRAFT'], doc);
    if (!result.ok) {
      await this.safeDelete(doc.storageKey);
      throw await this.notEditableError(applicationId);
    }
    if (result.previousKey) await this.safeDelete(result.previousKey);
  }

  private assertSupportedImage(file: UploadedFile, type: DocumentType): AllowedImageType {
    if (!file.buffer || file.size === 0) throw Errors.badRequest(`${type}: file is empty`);
    if (file.size > this.config.maxUploadBytes) {
      throw Errors.payloadTooLarge(`${type}: file exceeds ${this.config.maxUploadBytes} bytes`);
    }
    const detected = detectImageType(file.buffer);
    if (!detected) throw Errors.unsupportedMediaType(`${type}: only JPEG, PNG or WEBP images are accepted`);
    return detected;
  }

  evaluateCompleteness(app: KycApplicationWithRelations): KycCompleteness {
    const details = extractPersonalDetails(app);
    const provided = Object.fromEntries(Object.entries(details).filter(([, v]) => v !== null));

    const parsed = personalDetailsSchema.safeParse(provided);
    const fieldIssues = parsed.success ? crossFieldIssues(parsed.data) : formatZodIssues(parsed.error);

    const requiredDocuments = requiredDocumentsFor(details.idType);
    const uploaded = new Set(app.documents.map((d) => d.type));
    const missingDocuments = requiredDocuments.filter((t) => !uploaded.has(t));

    return {
      isComplete: fieldIssues.length === 0 && missingDocuments.length === 0,
      requiredDocuments,
      missingDocuments,
      fieldIssues,
    };
  }

  private async toView(app: KycApplicationWithRelations): Promise<KycApplicationView> {
    const status = toKycStatus(app.status);
    const editable = USER_EDITABLE_STATUSES.includes(status);

    const personalDetails = extractPersonalDetails(app);
    // Once submitted, the full ID number is never echoed back (PII minimisation).
    if (!editable) personalDetails.idNumber = maskIdentifier(personalDetails.idNumber);

    const documents = await Promise.all(
      [...app.documents]
        .sort((a, b) => DOCUMENT_TYPES.indexOf(a.type as DocumentType) - DOCUMENT_TYPES.indexOf(b.type as DocumentType))
        .map((doc) => this.toDocumentView(doc)),
    );

    return {
      id: app.id,
      status,
      version: app.version,
      currentStep: app.currentStep,
      personalDetails,
      documents,
      completeness: editable ? this.evaluateCompleteness(app) : null,
      allowedActions: allowedActionsFor(status),
      submittedAt: app.submittedAt,
      processingStartedAt: app.processingStartedAt,
      reviewedAt: app.reviewedAt,
      rejectionReason: app.rejectionReason,
      resubmissionItems: parseResubmissionItems(app.resubmissionItems),
      history: app.history.map((h) => ({
        fromStatus: h.fromStatus,
        toStatus: h.toStatus,
        actor: h.actor,
        reason: h.reason,
        at: h.createdAt,
      })),
      createdAt: app.createdAt,
      updatedAt: app.updatedAt,
    };
  }

  private async findDocumentView(app: KycApplicationWithRelations, type: DocumentType): Promise<KycDocumentView> {
    const doc = app.documents.find((d) => d.type === type);
    if (!doc) throw Errors.notFound(`No ${type} document uploaded`);
    return this.toDocumentView(doc);
  }

  private async toDocumentView(doc: KycDocument): Promise<KycDocumentView> {
    const { url, expiresAt } = await this.storage.createPresignedDownloadUrl(
      doc.storageKey,
      this.config.downloadTtlSeconds,
    );
    return {
      type: doc.type as DocumentType,
      contentType: doc.contentType,
      sizeBytes: doc.sizeBytes,
      uploadedAt: doc.updatedAt,
      url,
      urlExpiresAt: expiresAt,
    };
  }

  /** Non-guessable, per-user/per-application keys: <prefix>kyc/<userId>/<appId>/<type>-<uuid>.<ext> */
  private buildObjectKey(userId: string, applicationId: string, type: DocumentType, contentType: AllowedImageType) {
    return `${this.objectKeyPrefix(userId, applicationId, type)}${newId()}.${IMAGE_EXTENSIONS[contentType]}`;
  }

  private objectKeyPrefix(userId: string, applicationId: string, type: DocumentType): string {
    return `${this.config.keyPrefix}kyc/${userId}/${applicationId}/${type.toLowerCase()}-`;
  }

  private async safeDelete(key: string): Promise<void> {
    try {
      await this.storage.deleteObject(key);
    } catch (err) {
      this.logger.warn('Failed to delete orphaned object', { key, err });
    }
  }

  private notEditable(status: KycStatus): AppError {
    return Errors.conflict(
      `KYC application is ${status} and can no longer be modified`,
      'KYC_NOT_EDITABLE',
      { status },
    );
  }

  private async notEditableError(applicationId: string): Promise<AppError> {
    const app = await this.repo.findById(applicationId);
    return this.notEditable(app ? toKycStatus(app.status) : 'DRAFT');
  }
}

/** Maps a validated draft payload to DB columns (only fields that were provided). */
function toUpdateData(input: KycDraftInput): Prisma.KycApplicationUpdateManyMutationInput {
  const data: Prisma.KycApplicationUpdateManyMutationInput = {};
  for (const field of PERSONAL_DETAIL_FIELDS) {
    const value = input[field];
    if (value !== undefined) data[field] = value;
  }
  if (input.currentStep !== undefined) data.currentStep = input.currentStep;
  return data;
}
