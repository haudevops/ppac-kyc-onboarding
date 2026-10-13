import '../helpers/test-env';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { registerSchema } from '../../src/validators/auth.schema';
import {
  createUploadUrlSchema,
  crossFieldIssues,
  devReviewSchema,
  documentTypeParamsSchema,
  kycDraftSchema,
  personalDetailsSchema,
} from '../../src/validators/kyc.schema';
import { completeDetails } from '../helpers/fixtures';

describe('personal details validation', () => {
  it('accepts a complete form and normalises it', () => {
    const parsed = personalDetailsSchema.parse(completeDetails({ nationality: 'vn', idNumber: ' ab-12345 ' }));
    assert.equal(parsed.nationality, 'VN');
    assert.equal(parsed.idNumber, 'AB-12345');
  });

  it('reports every missing required field', () => {
    const result = personalDetailsSchema.safeParse({});
    assert.equal(result.success, false);
    const fields = result.success ? [] : result.error.issues.map((i) => i.path.join('.'));
    for (const f of ['fullName', 'dateOfBirth', 'nationality', 'addressLine1', 'city', 'country', 'idType', 'idNumber', 'idExpiryDate']) {
      assert.ok(fields.includes(f), `${f} should be required`);
    }
  });

  it('enforces age, real calendar dates and unexpired documents', () => {
    const year = new Date().getUTCFullYear();
    assert.equal(personalDetailsSchema.safeParse(completeDetails({ dateOfBirth: `${year - 10}-01-01` })).success, false);
    assert.equal(personalDetailsSchema.safeParse(completeDetails({ dateOfBirth: '1990-02-30' })).success, false);
    assert.equal(personalDetailsSchema.safeParse(completeDetails({ idExpiryDate: '2000-01-01' })).success, false);
    assert.equal(personalDetailsSchema.safeParse(completeDetails({ fullName: 'Nguyễn Văn An' })).success, true);
    assert.equal(personalDetailsSchema.safeParse(completeDetails({ fullName: '<script>' })).success, false);
  });

  it('checks rules spanning several fields', () => {
    assert.equal(crossFieldIssues({ idIssueDate: '2030-01-01', idExpiryDate: '2029-01-01' }).length, 1);
    assert.equal(crossFieldIssues({ dateOfBirth: '1990-01-01', idIssueDate: '1980-01-01' }).length, 1);
    assert.equal(crossFieldIssues(personalDetailsSchema.parse(completeDetails())).length, 0);
  });
});

describe('draft payload', () => {
  it('accepts partial data and treats empty strings as "not provided"', () => {
    const parsed = kycDraftSchema.parse({ fullName: 'Alice Nguyen', city: '', currentStep: 'document' });
    assert.deepEqual(parsed, { fullName: 'Alice Nguyen', currentStep: 'document' });
  });

  it('still validates the fields that are provided and rejects unknown keys', () => {
    assert.equal(kycDraftSchema.safeParse({ dateOfBirth: 'yesterday' }).success, false);
    assert.equal(kycDraftSchema.safeParse({ isAdmin: true }).success, false);
  });

  it('works with the null-prototype body produced by multer', () => {
    const body = Object.assign(Object.create(null), { city: 'Hanoi' }) as Record<string, string>;
    assert.equal(kycDraftSchema.safeParse(body).success, true);
  });
});

describe('other request schemas', () => {
  it('maps URL document types', () => {
    assert.equal(documentTypeParamsSchema.parse({ type: 'id-front' }).type, 'ID_FRONT');
    assert.equal(documentTypeParamsSchema.parse({ type: 'SELFIE' }).type, 'SELFIE');
    assert.equal(documentTypeParamsSchema.safeParse({ type: 'passport' }).success, false);
  });

  it('only allows image uploads within the size limit', () => {
    assert.equal(createUploadUrlSchema.safeParse({ contentType: 'image/jpeg', contentLength: 1000 }).success, true);
    assert.equal(createUploadUrlSchema.safeParse({ contentType: 'application/pdf' }).success, false);
    assert.equal(createUploadUrlSchema.safeParse({ contentType: 'image/png', contentLength: 50 * 1024 * 1024 }).success, false);
  });

  it('dev review accepts resubmission items', () => {
    assert.equal(devReviewSchema.safeParse({ decision: 'RESUBMISSION_REQUESTED', items: ['SELFIE'] }).success, true);
    assert.equal(devReviewSchema.safeParse({ decision: 'RESUBMISSION_REQUESTED', items: ['PASSWORD'] }).success, false);
  });

  it('password policy matches bcrypt limits', () => {
    assert.equal(registerSchema.safeParse({ email: 'a@b.co', password: 'Abcdefg1' }).success, true);
    assert.equal(registerSchema.safeParse({ email: 'a@b.co', password: 'abcdefgh' }).success, false);
    assert.equal(registerSchema.safeParse({ email: 'a@b.co', password: `Aa1${'x'.repeat(80)}` }).success, false);
    assert.equal(registerSchema.parse({ email: '  Alice@Example.COM ', password: 'Abcdefg1' }).email, 'alice@example.com');
  });
});
