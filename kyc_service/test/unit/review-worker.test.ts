import '../helpers/test-env';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { KycReviewWorker } from '../../src/jobs/kyc-review.worker';
import { KycAutoReviewer } from '../../src/services/kyc-reviewer.service';
import type { KycDraftInput } from '../../src/validators/kyc.schema';
import { JPEG, STRONG_PASSWORD, completeDetails } from '../helpers/fixtures';
import { createTestContext, silentLogger } from '../helpers/test-app';

const file = { buffer: JPEG, size: JPEG.length };

async function submitted(fullName: string) {
  const c = createTestContext();
  const { user } = await c.auth.register({ email: `${Math.random().toString(36).slice(2)}@example.com`, password: STRONG_PASSWORD }, {});
  await c.kycService.submit(user.id, completeDetails({ fullName }) as KycDraftInput, {
    ID_FRONT: file,
    ID_BACK: file,
    SELFIE: file,
  });
  return { ...c, userId: user.id };
}

describe('KycReviewWorker (simulated reviewer, rule mode)', () => {
  it('SUBMITTED -> PROCESSING -> APPROVED', async () => {
    const c = await submitted('Alice Nguyen');
    await c.worker.tick();
    const view = (await c.kycService.getOverview(c.userId)).application;
    assert.equal(view?.status, 'APPROVED');
    assert.deepEqual(view?.history.map((h) => [h.toStatus, h.actor]), [
      ['DRAFT', 'USER'],
      ['SUBMITTED', 'USER'],
      ['PROCESSING', 'SYSTEM'],
      ['APPROVED', 'SYSTEM'],
    ]);
  });

  it('waits for the configured delay before deciding', async () => {
    const c = await submitted('Alice Nguyen');
    const slowWorker = new KycReviewWorker(c.kyc.asRepository(), new KycAutoReviewer('rule'), silentLogger, {
      decisionDelayMs: 60_000,
      pollIntervalMs: 60_000,
      batchSize: 10,
    });
    await slowWorker.tick();
    assert.equal((await c.kycService.getStatus(c.userId)).status, 'PROCESSING');
  });

  it('"reject" in the name -> REJECTED (final)', async () => {
    const c = await submitted('Reject Tester');
    await c.worker.tick();
    const status = await c.kycService.getStatus(c.userId);
    assert.equal(status.status, 'REJECTED');
    assert.ok(status.rejectionReason);
  });

  it('"retake" -> selfie resubmission requested, then approved on the second submission', async () => {
    const c = await submitted('Retake Tester');
    await c.worker.tick();
    let status = await c.kycService.getStatus(c.userId);
    assert.equal(status.status, 'RESUBMISSION_REQUESTED');
    assert.deepEqual(status.resubmissionItems, ['SELFIE']);

    await c.kycService.submit(c.userId, {}, { SELFIE: file });
    await c.worker.tick();
    status = await c.kycService.getStatus(c.userId);
    assert.equal(status.status, 'APPROVED');
  });

  it('an expired ID at review time asks for new details and document photos', async () => {
    const c = await submitted('Alice Nguyen');
    const app = [...c.kyc.apps.values()][0];
    c.kyc.patch(app.id, { idExpiryDate: '2001-01-01' });
    await c.worker.tick();
    const status = await c.kycService.getStatus(c.userId);
    assert.equal(status.status, 'RESUBMISSION_REQUESTED');
    assert.deepEqual(status.resubmissionItems, ['PERSONAL_DETAILS', 'ID_FRONT', 'ID_BACK']);
  });

  it('two workers never apply the same decision twice', async () => {
    const c = await submitted('Alice Nguyen');
    const other = new KycReviewWorker(c.kyc.asRepository(), new KycAutoReviewer('rule'), silentLogger, {
      decisionDelayMs: 0,
      pollIntervalMs: 60_000,
      batchSize: 10,
    });
    await Promise.all([c.worker.tick(), other.tick()]);
    const transitions = c.kyc.history.map((h) => h.toStatus);
    assert.equal(transitions.filter((s) => s === 'PROCESSING').length, 1);
    assert.equal(transitions.filter((s) => s === 'APPROVED').length, 1);
  });
});
