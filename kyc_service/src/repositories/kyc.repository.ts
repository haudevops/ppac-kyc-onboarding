import type { Prisma, PrismaClient } from '@prisma/client';
import {
  type DocumentType,
  type KycActor,
  type KycApplicationWithRelations,
  type KycStatus,
  assertTransition,
  kycApplicationInclude,
  toKycStatus,
} from '../models/kyc.model';

export interface TransitionInput {
  id: string;
  /** Statuses the application is allowed to be in for this transition to apply. */
  from: readonly KycStatus[];
  to: KycStatus;
  actor: KycActor;
  reason?: string | null;
  data?: Prisma.KycApplicationUpdateManyMutationInput;
}

export interface DocumentInput {
  type: DocumentType;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  sha256?: string | null;
}

export interface KycStatusSnapshot {
  status: string;
  version: number;
  rejectionReason: string | null;
  resubmissionItems: string | null;
  submittedAt: Date | null;
  reviewedAt: Date | null;
  updatedAt: Date;
}

/**
 * Data access for KYC applications. All state changes are *conditional* updates
 * (`WHERE id = ? AND status IN (...)`) so concurrent requests / workers can never
 * apply an invalid or duplicate transition.
 */
export class KycRepository {
  constructor(private readonly db: PrismaClient) {}

  findByUserId(userId: string): Promise<KycApplicationWithRelations | null> {
    return this.db.kycApplication.findUnique({ where: { userId }, include: kycApplicationInclude });
  }

  findById(id: string): Promise<KycApplicationWithRelations | null> {
    return this.db.kycApplication.findUnique({ where: { id }, include: kycApplicationInclude });
  }

  findStatusByUserId(userId: string): Promise<KycStatusSnapshot | null> {
    return this.db.kycApplication.findUnique({
      where: { userId },
      select: {
        status: true,
        version: true,
        rejectionReason: true,
        resubmissionItems: true,
        submittedAt: true,
        reviewedAt: true,
        updatedAt: true,
      },
    });
  }

  /** Throws Prisma P2002 if the user already has an application (handled by the service). */
  createDraft(userId: string): Promise<KycApplicationWithRelations> {
    return this.db.kycApplication.create({
      data: {
        userId,
        status: 'DRAFT',
        history: { create: { fromStatus: null, toStatus: 'DRAFT', actor: 'USER', reason: 'Application started' } },
      },
      include: kycApplicationInclude,
    });
  }

  /** Updates draft fields only while the application is in one of `allowedStatuses`. */
  async updateFields(
    id: string,
    allowedStatuses: readonly KycStatus[],
    data: Prisma.KycApplicationUpdateManyMutationInput,
  ): Promise<boolean> {
    const { count } = await this.db.kycApplication.updateMany({
      where: { id, status: { in: [...allowedStatuses] } },
      data: { ...data, version: { increment: 1 } },
    });
    return count === 1;
  }

  /**
   * Applies a status transition + audit-log entry atomically.
   * Returns false when the application is no longer in an expected `from` status
   * (someone else moved it first) - callers decide whether that is an error.
   */
  async transition(input: TransitionInput): Promise<boolean> {
    for (const from of input.from) assertTransition(from, input.to);

    return this.db.$transaction(async (tx) => {
      const current = await tx.kycApplication.findUnique({ where: { id: input.id }, select: { status: true } });
      if (!current) return false;

      const currentStatus = toKycStatus(current.status);
      if (!input.from.includes(currentStatus)) return false;

      const { count } = await tx.kycApplication.updateMany({
        where: { id: input.id, status: currentStatus },
        data: { ...input.data, status: input.to, version: { increment: 1 } },
      });
      if (count === 0) return false;

      await tx.kycStatusHistory.create({
        data: {
          applicationId: input.id,
          fromStatus: currentStatus,
          toStatus: input.to,
          actor: input.actor,
          reason: input.reason ?? null,
        },
      });
      return true;
    });
  }

  /**
   * Inserts or replaces the document of a given type, only while the application is editable.
   * Returns the storage key of the replaced object (so the caller can delete it).
   */
  upsertDocument(
    applicationId: string,
    editableStatuses: readonly KycStatus[],
    doc: DocumentInput,
  ): Promise<{ ok: boolean; previousKey: string | null }> {
    return this.db.$transaction(async (tx) => {
      const app = await tx.kycApplication.findFirst({
        where: { id: applicationId, status: { in: [...editableStatuses] } },
        select: { id: true },
      });
      if (!app) return { ok: false, previousKey: null };

      const where = { applicationId_type: { applicationId, type: doc.type } };
      const existing = await tx.kycDocument.findUnique({ where, select: { storageKey: true } });

      const values = {
        storageKey: doc.storageKey,
        contentType: doc.contentType,
        sizeBytes: doc.sizeBytes,
        sha256: doc.sha256 ?? null,
      };
      await tx.kycDocument.upsert({
        where,
        create: { applicationId, type: doc.type, ...values },
        update: values,
      });
      await tx.kycApplication.update({ where: { id: applicationId }, data: { version: { increment: 1 } } });

      const previousKey = existing && existing.storageKey !== doc.storageKey ? existing.storageKey : null;
      return { ok: true, previousKey };
    });
  }

  /** Removes documents of the given types; returns their storage keys so the objects can be deleted. */
  deleteDocuments(applicationId: string, types: readonly DocumentType[]): Promise<string[]> {
    if (types.length === 0) return Promise.resolve([]);
    return this.db.$transaction(async (tx) => {
      const docs = await tx.kycDocument.findMany({
        where: { applicationId, type: { in: [...types] } },
        select: { storageKey: true },
      });
      await tx.kycDocument.deleteMany({ where: { applicationId, type: { in: [...types] } } });
      return docs.map((d) => d.storageKey);
    });
  }

  async findIdsByStatus(status: KycStatus, limit: number): Promise<string[]> {
    const rows = await this.db.kycApplication.findMany({
      where: { status },
      select: { id: true },
      orderBy: { submittedAt: 'asc' },
      take: limit,
    });
    return rows.map((r) => r.id);
  }

  /** PROCESSING applications whose review delay (measured from submission) has elapsed. */
  findDueForDecision(submittedBefore: Date, limit: number): Promise<KycApplicationWithRelations[]> {
    return this.db.kycApplication.findMany({
      where: { status: 'PROCESSING', submittedAt: { lte: submittedBefore } },
      include: kycApplicationInclude,
      orderBy: { submittedAt: 'asc' },
      take: limit,
    });
  }
}
