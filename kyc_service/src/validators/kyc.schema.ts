import { z } from 'zod';
import { env } from '../config/env';
import { DOCUMENT_TYPES, GENDERS, ID_TYPES, RESUBMISSION_ITEMS, REVIEW_DECISIONS } from '../models/kyc.model';
import { ALLOWED_IMAGE_TYPES } from '../utils/image';
import type { FieldIssue } from '../utils/zod';

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

const todayUtc = (): string => new Date().toISOString().slice(0, 10);

function isValidCalendarDate(value: string): boolean {
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
}

function isAtLeastYearsOld(dateOfBirth: string, years: number): boolean {
  const [y, m, d] = dateOfBirth.split('-');
  return `${Number(y) + years}-${m}-${d}` <= todayUtc();
}

const isoDate = z
  .string()
  .trim()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be a date in YYYY-MM-DD format')
  .refine(isValidCalendarDate, 'Must be a valid calendar date');

const countryCode = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{2}$/, 'Must be an ISO 3166-1 alpha-2 country code, e.g. VN');

/** Drops '', null and undefined so partial payloads (incl. multipart text fields) are treated as "not provided". */
function stripEmptyValues(value: unknown): unknown {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return value;
  return Object.fromEntries(
    Object.entries(value).filter(
      ([, v]) => v !== undefined && v !== null && !(typeof v === 'string' && v.trim() === ''),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* Personal details                                                   */
/* ------------------------------------------------------------------ */

/** Complete personal details - every required field must be present to submit. */
export const personalDetailsSchema = z.object({
  fullName: z
    .string()
    .trim()
    .min(2)
    .max(100)
    .regex(/^[\p{L}\p{M}' .-]+$/u, 'Full name contains invalid characters'),
  dateOfBirth: isoDate
    .refine((d) => d >= '1900-01-01' && d <= todayUtc(), 'Date of birth is out of range')
    .refine((d) => isAtLeastYearsOld(d, 18), 'You must be at least 18 years old'),
  gender: z.enum(GENDERS).optional(),
  nationality: countryCode,
  phoneNumber: z
    .string()
    .trim()
    .regex(/^\+[1-9]\d{7,14}$/, 'Must be in E.164 format, e.g. +84901234567')
    .optional(),
  addressLine1: z.string().trim().min(3).max(200),
  addressLine2: z.string().trim().max(200).optional(),
  city: z.string().trim().min(1).max(100),
  stateProvince: z.string().trim().max(100).optional(),
  postalCode: z.string().trim().max(20).optional(),
  country: countryCode,
  idType: z.enum(ID_TYPES),
  idNumber: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z0-9-]{5,30}$/, 'ID number must be 5-30 letters, digits or dashes'),
  idIssueDate: isoDate.refine((d) => d <= todayUtc(), 'Issue date cannot be in the future').optional(),
  idExpiryDate: isoDate.refine((d) => d > todayUtc(), 'The ID document has expired'),
});

export type PersonalDetailsInput = z.infer<typeof personalDetailsSchema>;

/** Rules that span several fields (checked at submit time against the merged draft). */
export function crossFieldIssues(details: Partial<PersonalDetailsInput>): FieldIssue[] {
  const issues: FieldIssue[] = [];
  if (details.idIssueDate && details.idExpiryDate && details.idIssueDate >= details.idExpiryDate) {
    issues.push({ field: 'idExpiryDate', message: 'Expiry date must be after the issue date' });
  }
  if (details.idIssueDate && details.dateOfBirth && details.idIssueDate < details.dateOfBirth) {
    issues.push({ field: 'idIssueDate', message: 'Issue date cannot be before the date of birth' });
  }
  return issues;
}

/**
 * Draft payload: every field optional, but each provided field must be well-formed.
 * Also used by POST /kyc/submit (the payload is merged with the saved draft and then
 * checked for completeness).
 */
export const kycDraftSchema = z.preprocess(
  stripEmptyValues,
  personalDetailsSchema
    .partial()
    .extend({
      currentStep: z.string().trim().min(1).max(64).optional(),
    })
    .strict(),
);

export type KycDraftInput = z.infer<typeof kycDraftSchema>;

/* ------------------------------------------------------------------ */
/* Documents                                                          */
/* ------------------------------------------------------------------ */

/** Accepts `id-front`, `ID_FRONT`, `selfie`, ... in the URL. */
export const documentTypeParamsSchema = z.object({
  type: z
    .string()
    .transform((value) => value.trim().toUpperCase().replace(/-/g, '_'))
    .pipe(z.enum(DOCUMENT_TYPES)),
});

export const createUploadUrlSchema = z
  .object({
    contentType: z.enum(ALLOWED_IMAGE_TYPES),
    contentLength: z.number().int().positive().max(env.MAX_UPLOAD_SIZE_BYTES).optional(),
  })
  .strict();

export const confirmUploadSchema = z
  .object({
    key: z.string().min(1).max(512),
  })
  .strict();

export const devReviewSchema = z
  .object({
    decision: z.enum(REVIEW_DECISIONS),
    reason: z.string().trim().min(1).max(500).optional(),
    /** For RESUBMISSION_REQUESTED (defaults to ["SELFIE"]). */
    items: z.array(z.enum(RESUBMISSION_ITEMS)).min(1).max(RESUBMISSION_ITEMS.length).optional(),
  })
  .strict();

export type DocumentTypeParams = z.infer<typeof documentTypeParamsSchema>;
export type CreateUploadUrlInput = z.infer<typeof createUploadUrlSchema>;
export type ConfirmUploadInput = z.infer<typeof confirmUploadSchema>;
export type DevReviewInput = z.infer<typeof devReviewSchema>;
