import '../helpers/test-env';

import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { env } from '../../src/config/env';
import { createContainer, type Container } from '../../src/container';
import { connectDatabase } from '../../src/database/prisma';
import { LocalStorageProvider } from '../../src/storage/local.storage';
import { JPEG, PNG, STRONG_PASSWORD, completeDetails } from '../helpers/fixtures';
import { silentLogger, startServer } from '../helpers/test-app';

/**
 * End-to-end against the REAL Prisma repositories and a throw-away SQLite database
 * (`npm run test:e2e` resets prisma/test.db first). Covers what the in-memory unit tests cannot:
 * SQL conditional updates, transactions, unique constraints and the worker against the DB.
 */
describe('API end-to-end (SQLite)', () => {
  let container: Container;
  let server: Awaited<ReturnType<typeof startServer>>;

  const register = async (fullName: string) => {
    const res = await server.api('POST', '/api/v1/auth/register', {
      json: { email: `${Math.random().toString(36).slice(2)}@example.com`, password: STRONG_PASSWORD, fullName },
    });
    assert.equal(res.status, 201);
    return res.body.data.tokens.accessToken as string;
  };

  const submitAll = async (token: string, fullName: string) => {
    const form = new FormData();
    for (const [k, v] of Object.entries(completeDetails({ fullName }))) form.append(k, v);
    for (const field of ['idFront', 'idBack', 'selfie']) form.append(field, new Blob([new Uint8Array(JPEG)]), `${field}.jpg`);
    return server.api('POST', '/api/v1/kyc/submit', { token, form });
  };

  before(async () => {
    assert.match(env.DATABASE_URL, /test\.db/, 'refusing to run e2e tests against a non-test database');
    container = createContainer(env, silentLogger);
    await connectDatabase(container.prisma, env, silentLogger);
    if (container.storage instanceof LocalStorageProvider) await container.storage.init();
    server = await startServer(container);
  });

  after(async () => {
    await server.close();
    await container.prisma.$disconnect();
  });

  it('approves a normal applicant', async () => {
    const token = await register('Alice Nguyen');
    const submitted = await submitAll(token, 'Alice Nguyen');
    assert.equal(submitted.status, 202, JSON.stringify(submitted.body));

    await container.reviewWorker.tick();
    const status = await server.api('GET', '/api/v1/kyc/status', { token });
    assert.equal(status.body.data.status, 'APPROVED');
  });

  it('handles a resubmission request end to end', async () => {
    const token = await register('Retake Tester');
    await submitAll(token, 'Retake Tester');
    await container.reviewWorker.tick();

    const requested = await server.api('GET', '/api/v1/kyc', { token });
    assert.equal(requested.body.data.status, 'RESUBMISSION_REQUESTED');
    assert.deepEqual(requested.body.data.application.resubmissionItems, ['SELFIE']);

    // Upload a new selfie (re-opens the application), then submit the rest unchanged.
    const form = new FormData();
    form.append('file', new Blob([new Uint8Array(PNG)]), 'selfie.png');
    const upload = await server.api('POST', '/api/v1/kyc/documents/selfie', { token, form });
    assert.equal(upload.status, 201);

    const resubmit = await server.api('POST', '/api/v1/kyc/submit', { token, json: {} });
    assert.equal(resubmit.status, 202, JSON.stringify(resubmit.body));
    await container.reviewWorker.tick();

    const final = await server.api('GET', '/api/v1/kyc', { token });
    assert.equal(final.body.data.status, 'APPROVED');
    assert.deepEqual(
      final.body.data.application.history.map((h: { toStatus: string }) => h.toStatus),
      ['DRAFT', 'SUBMITTED', 'PROCESSING', 'RESUBMISSION_REQUESTED', 'DRAFT', 'SUBMITTED', 'PROCESSING', 'APPROVED'],
    );
  });

  it('rejection is final', async () => {
    const token = await register('Reject Tester');
    await submitAll(token, 'Reject Tester');
    await container.reviewWorker.tick();
    const edit = await server.api('PUT', '/api/v1/kyc/draft', { token, json: { city: 'Hanoi' } });
    assert.equal(edit.status, 409);
  });

  it('concurrent submits only submit once (conditional update in SQL)', async () => {
    const token = await register('Alice Nguyen');
    const results = await Promise.all([submitAll(token, 'Alice Nguyen'), submitAll(token, 'Alice Nguyen')]);
    const statuses = results.map((r) => r.status).sort();
    assert.ok(statuses.includes(202), JSON.stringify(statuses));
    const kyc = await server.api('GET', '/api/v1/kyc', { token });
    const submits = kyc.body.data.application.history.filter((h: { toStatus: string }) => h.toStatus === 'SUBMITTED');
    assert.equal(submits.length, 1);
  });
});
