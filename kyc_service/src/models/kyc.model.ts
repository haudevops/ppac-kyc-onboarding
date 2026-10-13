import type { Prisma } from '@prisma/client';
import { Errors } from '../utils/errors';

/* ------------------------------------------------------------------ */
/* Status state machine                                               */
/* ------------------------------------------------------------------ */

export const KYC_STATUSES = [
  'DRAFT',
  'SUBMITTED',
  'PROCESSING',
  'APPROVED',
  'REJECTED',
  'RESUBMISSION_REQUESTED',
] as const;
export type KycStatus = (typeof KYC_STATUSES)[number];

/** Returned by GET /kyc when the user has never started an application. */
export const NOT_STARTED = 'NOT_STARTED' as const;

/**
 *   DRAFT ──submit──▶ SUBMITTED ──worker──▶ PROCESSING ──▶ APPROVED  (final)
 *     ▲                                          ├──────▶ REJECTED  (final, e.g. suspected fraud)
 *     │                                          └──────▶ RESUBMISSION_REQUESTED
 *     └──────────── user fixes the requested items ◀────────────┘
 *
 * Assumption (the brief separates "rejection" from "resubmission requests"):
 *  - REJECTED is a final decision - the user cannot resubmit (they would contact support).
 *  - RESUBMISSION_REQUESTED lists the items to redo (e.g. a blurry selfie); the application
 *    is re-opened as DRAFT on the user's first edit and the requested photos must be retaken.
 */
export const KYC_TRANSITIONS: Readonly<Record<KycStatus, readonly KycStatus[]>> = {
  DRAFT: ['SUBMITTED'],
  SUBMITTED: ['PROCESSING'],
  PROCESSING: ['APPROVED', 'REJECTED', 'RESUBMISSION_REQUESTED'],
  APPROVED: [],
  REJECTED: [],
  RESUBMISSION_REQUESTED: ['DRAFT'],
};

export function canTransition(from: KycStatus, to: KycStatus): boolean {
  return KYC_TRANSITIONS[from].includes(to);
}

export function assertTransition(from: KycStatus, to: KycStatus): void {
  if (!canTransition(from, to)) {
    throw Errors.conflict(`Invalid KYC status transition ${from} -> ${to}`, 'KYC_INVALID_TRANSITION', {
      from,
      to,
      allowed: KYC_TRANSITIONS[from],
    });
  }
}

export function toKycStatus(value: string): KycStatus {
  if ((KYC_STATUSES as readonly string[]).includes(value)) return value as KycStatus;
  throw Errors.internal(`Unknown KYC status in database: ${value}`);
}

/** Statuses in which the user may still change data (RESUBMISSION_REQUESTED is re-opened to DRAFT on first edit). */
export const USER_EDITABLE_STATUSES: readonly KycStatus[] = ['DRAFT', 'RESUBMISSION_REQUESTED'];

/** Decisions the reviewer can take on a PROCESSING application. */
export const REVIEW_DECISIONS = ['APPROVED', 'REJECTED', 'RESUBMISSION_REQUESTED'] as const;
export type ReviewDecisionStatus = (typeof REVIEW_DECISIONS)[number];

/** What a reviewer can ask the user to redo. */
export const RESUBMISSION_ITEMS = ['PERSONAL_DETAILS', 'ID_FRONT', 'ID_BACK', 'SELFIE'] as const;
export type ResubmissionItem = (typeof RESUBMISSION_ITEMS)[number];

export function parseResubmissionItems(raw: string | null | undefined): ResubmissionItem[] {
  if (!raw) return [];
  try {
    const value: unknown = JSON.parse(raw);
    return Array.isArray(value)
      ? value.filter((v): v is ResubmissionItem => (RESUBMISSION_ITEMS as readonly unknown[]).includes(v))
      : [];
  } catch {
    return [];
  }
}

export type KycActor = 'USER' | 'SYSTEM';

export type KycAction = 'SAVE_DRAFT' | 'UPLOAD_DOCUMENT' | 'SUBMIT' | 'WAIT_FOR_REVIEW' | 'RESUBMIT';

export function allowedActionsFor(status: KycStatus | typeof NOT_STARTED): KycAction[] {
  switch (status) {
    case NOT_STARTED:
    case 'DRAFT':
      return ['SAVE_DRAFT', 'UPLOAD_DOCUMENT', 'SUBMIT'];
    case 'RESUBMISSION_REQUESTED':
      return ['RESUBMIT', 'SAVE_DRAFT', 'UPLOAD_DOCUMENT', 'SUBMIT'];
    case 'SUBMITTED':
    case 'PROCESSING':
      return ['WAIT_FOR_REVIEW'];
    case 'APPROVED':
    case 'REJECTED':
      return [];
  }
}

/* ------------------------------------------------------------------ */
/* Documents & personal details                                       */
/* ------------------------------------------------------------------ */

export const DOCUMENT_TYPES = ['ID_FRONT', 'ID_BACK', 'SELFIE'] as const;
export type DocumentType = (typeof DOCUMENT_TYPES)[number];

export const ID_TYPES = ['NATIONAL_ID', 'PASSPORT', 'DRIVER_LICENSE'] as const;
export type IdType = (typeof ID_TYPES)[number];

export const GENDERS = ['MALE', 'FEMALE', 'OTHER'] as const;

/** A passport has no back side; every other ID type needs both sides. */
export function requiredDocumentsFor(idType: string | null | undefined): DocumentType[] {
  return idType === 'PASSPORT' ? ['ID_FRONT', 'SELFIE'] : ['ID_FRONT', 'ID_BACK', 'SELFIE'];
}

/** Multipart field names accepted by POST /kyc/submit, mapped to document types. */
export const SUBMIT_FILE_FIELDS: Readonly<Record<string, DocumentType>> = {
  idFront: 'ID_FRONT',
  idBack: 'ID_BACK',
  selfie: 'SELFIE',
};

export const PERSONAL_DETAIL_FIELDS = [
  'fullName',
  'dateOfBirth',
  'gender',
  'nationality',
  'phoneNumber',
  'addressLine1',
  'addressLine2',
  'city',
  'stateProvince',
  'postalCode',
  'country',
  'idType',
  'idNumber',
  'idIssueDate',
  'idExpiryDate',
] as const;
export type PersonalDetailField = (typeof PERSONAL_DETAIL_FIELDS)[number];
export type PersonalDetailsRecord = Record<PersonalDetailField, string | null>;

/* ------------------------------------------------------------------ */
/* Persistence shapes                                                 */
/* ------------------------------------------------------------------ */

export const kycApplicationInclude = {
  documents: true,
  history: { orderBy: { createdAt: 'asc' } },
} satisfies Prisma.KycApplicationInclude;

export type KycApplicationWithRelations = Prisma.KycApplicationGetPayload<{
  include: typeof kycApplicationInclude;
}>;

export function extractPersonalDetails(app: PersonalDetailsRecord): PersonalDetailsRecord {
  const out = {} as PersonalDetailsRecord;
  for (const field of PERSONAL_DETAIL_FIELDS) out[field] = app[field] ?? null;
  return out;
}

/** Keeps only the last 4 characters of an identifier, e.g. "********1234". */
export function maskIdentifier(value: string | null): string | null {
  if (!value) return value;
  if (value.length <= 4) return '*'.repeat(value.length);
  return `${'*'.repeat(value.length - 4)}${value.slice(-4)}`;
}
