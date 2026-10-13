import '../helpers/test-env';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { KycDraftInput } from '../../src/validators/kyc.schema';
import { AppError } from '../../src/utils/errors';
import { JPEG, PDF, PNG, STRONG_PASSWORD, completeDetails } from '../helpers/fixtures';
import { createTestContext } from '../helpers/test-app';

const hasCode = (code: string) => (e: unknown) => e instanceof AppError && e.code === code;
const file = (buffer: Buffer) => ({ buffer, size: buffer.length });
const details = (overrides: Record<string, string> = {}) => completeDetails(overrides) as KycDraftInput;

async function setup(fullName = 'Alice Nguyen') {
  const context = createTestContext();
  const { user } = await context.auth.register(
    { email: `${Math.random().toString(36).slice(2)}@example.com`, password: STRONG_PASSWORD },
    {},
  );
  return { ...context, userId: user.id, fullName };
}

/** Uploads all three photos and submits complete details. */
async function submitComplete(c: Awaited<ReturnType<typeof setup>>) {
  for (const type of ['ID_FRONT', 'ID_BACK', 'SELFIE'] as const) {
    await c.kycService.uploadDocument(c.userId, type, file(JPEG));
  }
  return c.kycService.submit(c.userId, details({ fullName: c.fullName }), {});
}

describe('KycService - drafts and documents', () => {
  it('starts as NOT_STARTED and creates a draft on first save', async () => {
    const c = await setup();
    assert.equal((await c.kycService.getOverview(c.userId)).status, 'NOT_STARTED');

    const view = await c.kycService.saveDraft(c.userId, { fullName: 'Alice Nguyen', currentStep: 'document' });
    assert.equal(view.status, 'DRAFT');
    assert.equal(view.currentStep, 'document');
    assert.equal(view.personalDetails.fullName, 'Alice Nguyen');
    assert.equal(view.completeness?.isComplete, false);
  });

  it('rejects files that are not images, whatever their declared type', async () => {
    const c = await setup();
    await assert.rejects(c.kycService.uploadDocument(c.userId, 'SELFIE', file(PDF)), hasCode('UNSUPPORTED_MEDIA_TYPE'));
  });

  it('replacing a photo deletes the previous object', async () => {
    const c = await setup();
    await c.kycService.uploadDocument(c.userId, 'SELFIE', file(PNG));
    const [first] = c.kyc.documents;
    await c.kycService.uploadDocument(c.userId, 'SELFIE', file(JPEG));

    assert.equal(c.kyc.documents.length, 1);
    assert.notEqual(c.kyc.documents[0].storageKey, first.storageKey);
    assert.equal(await c.storage.getObjectMetadata(first.storageKey), null);
    assert.equal(c.kyc.documents[0].contentType, 'image/jpeg');
  });

  it('direct upload: presigned URL + confirm verifies ownership and real content', async () => {
    const c = await setup();
    const ticket = await c.kycService.createUploadUrl(c.userId, 'ID_FRONT', { contentType: 'image/png' });
    assert.match(ticket.key, new RegExp(`^kyc/${c.userId}/`));

    // Confirming before uploading fails; a key from another user/type is refused.
    await assert.rejects(c.kycService.confirmUpload(c.userId, 'ID_FRONT', ticket.key), hasCode('NOT_FOUND'));
    await assert.rejects(c.kycService.confirmUpload(c.userId, 'SELFIE', ticket.key), hasCode('FORBIDDEN'));

    // "Client uploads" a PDF disguised as PNG -> rejected and deleted.
    await c.storage.putObject({ key: ticket.key, body: PDF, contentType: 'image/png' });
    await assert.rejects(c.kycService.confirmUpload(c.userId, 'ID_FRONT', ticket.key), hasCode('UNSUPPORTED_MEDIA_TYPE'));
    assert.equal(await c.storage.getObjectMetadata(ticket.key), null);

    await c.storage.putObject({ key: ticket.key, body: PNG, contentType: 'image/png' });
    const doc = await c.kycService.confirmUpload(c.userId, 'ID_FRONT', ticket.key);
    assert.equal(doc.type, 'ID_FRONT');
    assert.ok(doc.url.startsWith('http'));
  });
});

describe('KycService - submission', () => {
  it('an incomplete submit returns KYC_INCOMPLETE but keeps what was sent', async () => {
    const c = await setup();
    await assert.rejects(
      c.kycService.submit(c.userId, { fullName: 'Alice Nguyen', city: 'Hanoi' }, { SELFIE: file(PNG) }),
      (e: unknown) => {
        assert.ok(e instanceof AppError && e.code === 'KYC_INCOMPLETE' && e.statusCode === 422);
        const details = e.details as { missingDocuments: string[]; fieldIssues: { field: string }[] };
        assert.deepEqual(details.missingDocuments, ['ID_FRONT', 'ID_BACK']);
        assert.ok(details.fieldIssues.some((i) => i.field === 'dateOfBirth'));
        return true;
      },
    );
    const view = (await c.kycService.getOverview(c.userId)).application;
    assert.equal(view?.status, 'DRAFT');
    assert.equal(view?.personalDetails.city, 'Hanoi');
    assert.deepEqual(view?.documents.map((d) => d.type), ['SELFIE']);
  });

  it('a complete submit moves to SUBMITTED, masks the ID number and locks editing', async () => {
    const c = await setup();
    const view = await submitComplete(c);
    assert.equal(view.status, 'SUBMITTED');
    assert.equal(view.personalDetails.idNumber, '********1234');
    assert.deepEqual(view.allowedActions, ['WAIT_FOR_REVIEW']);

    await assert.rejects(c.kycService.saveDraft(c.userId, { city: 'Hanoi' }), hasCode('KYC_NOT_EDITABLE'));
    await assert.rejects(c.kycService.uploadDocument(c.userId, 'SELFIE', file(PNG)), hasCode('KYC_NOT_EDITABLE'));
    await assert.rejects(submitComplete(c), hasCode('KYC_NOT_EDITABLE'));
  });

  it('a passport does not require the back side', async () => {
    const c = await setup();
    await c.kycService.uploadDocument(c.userId, 'ID_FRONT', file(PNG));
    await c.kycService.uploadDocument(c.userId, 'SELFIE', file(PNG));
    const view = await c.kycService.submit(c.userId, details({ idType: 'PASSPORT', idNumber: 'C1234567' }), {});
    assert.equal(view.status, 'SUBMITTED');
  });
});

describe('KycService - review outcomes', () => {
  it('REJECTED is final', async () => {
    const c = await setup();
    await submitComplete(c);
    const view = await c.kycService.forceReview(c.userId, { decision: 'REJECTED', reason: 'Fraud suspected' });
    assert.equal(view.status, 'REJECTED');
    assert.equal(view.rejectionReason, 'Fraud suspected');
    assert.deepEqual(view.allowedActions, []);
    await assert.rejects(c.kycService.saveDraft(c.userId, { city: 'Hanoi' }), hasCode('KYC_NOT_EDITABLE'));
  });

  it('a resubmission request re-opens the application and forces the requested photo to be retaken', async () => {
    const c = await setup();
    await submitComplete(c);
    const requested = await c.kycService.forceReview(c.userId, {
      decision: 'RESUBMISSION_REQUESTED',
      reason: 'Blurry selfie',
      items: ['SELFIE'],
    });
    assert.equal(requested.status, 'RESUBMISSION_REQUESTED');
    assert.deepEqual(requested.resubmissionItems, ['SELFIE']);
    assert.equal(requested.personalDetails.idNumber, '079090001234', 'editable again -> unmasked');
    const oldSelfie = c.kyc.documents.find((d) => d.type === 'SELFIE')?.storageKey as string;

    // First edit re-opens it as DRAFT, drops the old selfie, keeps the reviewer's feedback.
    const reopened = await c.kycService.saveDraft(c.userId, { currentStep: 'selfie' });
    assert.equal(reopened.status, 'DRAFT');
    assert.deepEqual(reopened.resubmissionItems, ['SELFIE']);
    assert.equal(reopened.rejectionReason, 'Blurry selfie');
    assert.deepEqual(reopened.completeness?.missingDocuments, ['SELFIE']);
    assert.equal(await c.storage.getObjectMetadata(oldSelfie), null);

    await assert.rejects(c.kycService.submit(c.userId, {}, {}), hasCode('KYC_INCOMPLETE'));
    const resubmitted = await c.kycService.submit(c.userId, {}, { SELFIE: file(PNG) });
    assert.equal(resubmitted.status, 'SUBMITTED');
    assert.equal(resubmitted.rejectionReason, null);
    assert.deepEqual(resubmitted.resubmissionItems, []);
    assert.deepEqual(
      resubmitted.history.map((h) => h.toStatus),
      ['DRAFT', 'SUBMITTED', 'PROCESSING', 'RESUBMISSION_REQUESTED', 'DRAFT', 'SUBMITTED'],
    );
  });

  it('getStatus exposes the reviewer feedback for polling', async () => {
    const c = await setup();
    await submitComplete(c);
    await c.kycService.forceReview(c.userId, { decision: 'RESUBMISSION_REQUESTED', items: ['ID_FRONT', 'ID_BACK'] });
    const status = await c.kycService.getStatus(c.userId);
    assert.equal(status.status, 'RESUBMISSION_REQUESTED');
    assert.deepEqual(status.resubmissionItems, ['ID_FRONT', 'ID_BACK']);
    assert.ok(status.allowedActions.includes('RESUBMIT'));
  });
});
