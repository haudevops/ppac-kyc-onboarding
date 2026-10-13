import { Prisma, type KycDocument, type KycStatusHistory, type RefreshToken, type User } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import {
  type DocumentType,
  type KycApplicationWithRelations,
  type KycStatus,
  assertTransition,
  toKycStatus,
} from '../../src/models/kyc.model';
import type { KycRepository, KycStatusSnapshot, TransitionInput, DocumentInput } from '../../src/repositories/kyc.repository';
import type { NewRefreshToken, RefreshTokenRepository } from '../../src/repositories/refresh-token.repository';
import type { UserRepository } from '../../src/repositories/user.repository';

/*
 * In-memory implementations with the same contract as the Prisma repositories (including the
 * conditional "only if still in status X" semantics). They let the service / HTTP tests run
 * without a database; test/e2e covers the real Prisma repositories against SQLite.
 */

let tick = 0;
/** Strictly increasing timestamps so ordering by createdAt is deterministic. */
const now = () => new Date(Date.now() + tick++);

const uniqueViolation = () =>
  new Prisma.PrismaClientKnownRequestError('Unique constraint failed', { code: 'P2002', clientVersion: 'test' });

type AppRecord = Omit<KycApplicationWithRelations, 'documents' | 'history'>;

function applyUpdate(target: Record<string, unknown>, data: Record<string, unknown> | undefined) {
  for (const [key, value] of Object.entries(data ?? {})) {
    if (value && typeof value === 'object' && !(value instanceof Date)) {
      const op = value as { increment?: number; set?: unknown };
      if (op.increment !== undefined) target[key] = (target[key] as number) + op.increment;
      else if ('set' in op) target[key] = op.set;
    } else if (value !== undefined) {
      target[key] = value;
    }
  }
}

export class InMemoryUserRepository {
  readonly users = new Map<string, User>();

  async findById(id: string) {
    return this.users.get(id) ?? null;
  }

  async findByEmail(email: string) {
    return [...this.users.values()].find((u) => u.email === email) ?? null;
  }

  async create(data: { email: string; passwordHash: string; fullName?: string | null }) {
    if (await this.findByEmail(data.email)) throw uniqueViolation();
    const user: User = {
      id: randomUUID(),
      email: data.email,
      passwordHash: data.passwordHash,
      fullName: data.fullName ?? null,
      createdAt: now(),
      updatedAt: now(),
    };
    this.users.set(user.id, user);
    return user;
  }

  asRepository() {
    return this as unknown as UserRepository;
  }
}

export class InMemoryRefreshTokenRepository {
  readonly tokens = new Map<string, RefreshToken>();

  async findById(id: string) {
    return this.tokens.get(id) ?? null;
  }

  async create(token: NewRefreshToken) {
    this.tokens.set(token.id, {
      ...token,
      userAgent: token.userAgent ?? null,
      ip: token.ip ?? null,
      revokedAt: null,
      replacedById: null,
      createdAt: now(),
    });
  }

  async rotate(oldId: string, replacement: NewRefreshToken) {
    const old = this.tokens.get(oldId);
    if (!old || old.revokedAt) return false;
    old.revokedAt = now();
    old.replacedById = replacement.id;
    await this.create(replacement);
    return true;
  }

  async revokeFamily(familyId: string) {
    let count = 0;
    for (const t of this.tokens.values()) {
      if (t.familyId === familyId && !t.revokedAt) {
        t.revokedAt = now();
        count++;
      }
    }
    return count;
  }

  async deleteExpired() {
    return 0;
  }

  asRepository() {
    return this as unknown as RefreshTokenRepository;
  }
}

export class InMemoryKycRepository {
  readonly apps = new Map<string, AppRecord>();
  documents: KycDocument[] = [];
  history: KycStatusHistory[] = [];

  private withRelations(app: AppRecord): KycApplicationWithRelations {
    return {
      ...app,
      documents: this.documents.filter((d) => d.applicationId === app.id).map((d) => ({ ...d })),
      history: this.history
        .filter((h) => h.applicationId === app.id)
        .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
        .map((h) => ({ ...h })),
    };
  }

  private byUser(userId: string) {
    return [...this.apps.values()].find((a) => a.userId === userId);
  }

  async findByUserId(userId: string) {
    const app = this.byUser(userId);
    return app ? this.withRelations(app) : null;
  }

  async findById(id: string) {
    const app = this.apps.get(id);
    return app ? this.withRelations(app) : null;
  }

  async findStatusByUserId(userId: string): Promise<KycStatusSnapshot | null> {
    const app = this.byUser(userId);
    if (!app) return null;
    const { status, version, rejectionReason, resubmissionItems, submittedAt, reviewedAt, updatedAt } = app;
    return { status, version, rejectionReason, resubmissionItems, submittedAt, reviewedAt, updatedAt };
  }

  async createDraft(userId: string) {
    if (this.byUser(userId)) throw uniqueViolation();
    const created = now();
    const app: AppRecord = {
      id: randomUUID(),
      userId,
      status: 'DRAFT',
      currentStep: null,
      version: 0,
      fullName: null,
      dateOfBirth: null,
      gender: null,
      nationality: null,
      phoneNumber: null,
      addressLine1: null,
      addressLine2: null,
      city: null,
      stateProvince: null,
      postalCode: null,
      country: null,
      idType: null,
      idNumber: null,
      idIssueDate: null,
      idExpiryDate: null,
      submittedAt: null,
      processingStartedAt: null,
      reviewedAt: null,
      rejectionReason: null,
      resubmissionItems: null,
      createdAt: created,
      updatedAt: created,
    };
    this.apps.set(app.id, app);
    this.addHistory(app.id, null, 'DRAFT', 'USER', 'Application started');
    return this.withRelations(app);
  }

  async updateFields(id: string, allowed: readonly KycStatus[], data: Prisma.KycApplicationUpdateManyMutationInput) {
    const app = this.apps.get(id);
    if (!app || !allowed.includes(toKycStatus(app.status))) return false;
    applyUpdate(app as unknown as Record<string, unknown>, data as Record<string, unknown>);
    app.version++;
    app.updatedAt = now();
    return true;
  }

  async transition(input: TransitionInput) {
    for (const from of input.from) assertTransition(from, input.to);
    const app = this.apps.get(input.id);
    if (!app) return false;
    const current = toKycStatus(app.status);
    if (!input.from.includes(current)) return false;

    applyUpdate(app as unknown as Record<string, unknown>, input.data as Record<string, unknown>);
    app.status = input.to;
    app.version++;
    app.updatedAt = now();
    this.addHistory(app.id, current, input.to, input.actor, input.reason ?? null);
    return true;
  }

  async upsertDocument(applicationId: string, editable: readonly KycStatus[], doc: DocumentInput) {
    const app = this.apps.get(applicationId);
    if (!app || !editable.includes(toKycStatus(app.status))) return { ok: false, previousKey: null };

    const existing = this.documents.find((d) => d.applicationId === applicationId && d.type === doc.type);
    const previousKey = existing && existing.storageKey !== doc.storageKey ? existing.storageKey : null;
    this.documents = this.documents.filter((d) => d !== existing);
    this.documents.push({
      id: randomUUID(),
      applicationId,
      type: doc.type,
      storageKey: doc.storageKey,
      contentType: doc.contentType,
      sizeBytes: doc.sizeBytes,
      sha256: doc.sha256 ?? null,
      createdAt: now(),
      updatedAt: now(),
    });
    app.version++;
    return { ok: true, previousKey };
  }

  async deleteDocuments(applicationId: string, types: readonly DocumentType[]) {
    const removed = this.documents.filter((d) => d.applicationId === applicationId && types.includes(d.type as DocumentType));
    this.documents = this.documents.filter((d) => !removed.includes(d));
    return removed.map((d) => d.storageKey);
  }

  async findIdsByStatus(status: KycStatus, limit: number) {
    return [...this.apps.values()].filter((a) => a.status === status).slice(0, limit).map((a) => a.id);
  }

  async findDueForDecision(submittedBefore: Date, limit: number) {
    return [...this.apps.values()]
      .filter((a) => a.status === 'PROCESSING' && a.submittedAt && a.submittedAt <= submittedBefore)
      .slice(0, limit)
      .map((a) => this.withRelations(a));
  }

  /** Test helper: change a column directly (e.g. simulate an expired ID). */
  patch(applicationId: string, data: Partial<AppRecord>) {
    Object.assign(this.apps.get(applicationId) as AppRecord, data);
  }

  private addHistory(applicationId: string, fromStatus: string | null, toStatus: string, actor: string, reason: string | null) {
    this.history.push({ id: randomUUID(), applicationId, fromStatus, toStatus, actor, reason, createdAt: now() });
  }

  asRepository() {
    return this as unknown as KycRepository;
  }
}
