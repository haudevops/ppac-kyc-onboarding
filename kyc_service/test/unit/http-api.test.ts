import '../helpers/test-env';

import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { JPEG, PDF, PNG, STRONG_PASSWORD, completeDetails } from '../helpers/fixtures';
import { createTestContext, startServer } from '../helpers/test-app';

/**
 * HTTP layer (routing, middleware, validation, error envelope, multipart, signed file URLs)
 * on top of the real services with in-memory repositories.
 */
describe('HTTP API', () => {
  const context = createTestContext();
  let server: Awaited<ReturnType<typeof startServer>>;
  let token: string;

  const imageForm = (field: string, buffer: Buffer, extra: Record<string, string> = {}) => {
    const form = new FormData();
    form.append(field, new Blob([new Uint8Array(buffer)]), `${field}.bin`); // no MIME type on purpose
    for (const [k, v] of Object.entries(extra)) form.append(k, v);
    return form;
  };

  before(async () => {
    server = await startServer(context.container);
    const res = await server.api('POST', '/api/v1/auth/register', {
      json: { email: 'http@example.com', password: STRONG_PASSWORD, fullName: 'Http Tester' },
    });
    assert.equal(res.status, 201);
    token = res.body.data.tokens.accessToken;
  });

  after(() => server.close());

  it('uses a consistent error envelope with a request id', async () => {
    const res = await server.api('GET', '/api/v1/nope');
    assert.equal(res.status, 404);
    assert.equal(res.body.success, false);
    assert.equal(res.body.error.code, 'NOT_FOUND');
    assert.equal(res.body.requestId, res.headers.get('x-request-id'));
  });

  it('returns field-level validation errors', async () => {
    const res = await server.api('POST', '/api/v1/auth/register', { json: { email: 'not-an-email', password: 'short' } });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    const fields = res.body.error.details.map((d: { field: string }) => d.field);
    assert.ok(fields.includes('body.email') && fields.includes('body.password'));
  });

  it('rejects malformed JSON with 400 instead of 500', async () => {
    const res = await fetch(`${server.baseUrl}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"email":',
    });
    assert.equal(res.status, 400);
  });

  it('protects KYC endpoints', async () => {
    assert.equal((await server.api('GET', '/api/v1/kyc')).status, 401);
    assert.equal((await server.api('GET', '/api/v1/kyc', { token: 'garbage' })).status, 401);
    const ok = await server.api('GET', '/api/v1/kyc', { token });
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get('cache-control'), 'no-store');
  });

  it('sniffs uploads by content (multipart without a MIME type is fine, a PDF is not)', async () => {
    const pdf = await server.api('POST', '/api/v1/kyc/documents/selfie', { token, form: imageForm('file', PDF) });
    assert.equal(pdf.status, 415);
    const png = await server.api('POST', '/api/v1/kyc/documents/selfie', { token, form: imageForm('file', PNG) });
    assert.equal(png.status, 201);
    assert.equal(png.body.data.document.contentType, 'image/png');
  });

  it('rejects files over the size limit with 413', async () => {
    const big = Buffer.concat([JPEG, Buffer.alloc(2 * 1024 * 1024)]);
    const res = await server.api('POST', '/api/v1/kyc/documents/id-front', { token, form: imageForm('file', big) });
    assert.equal(res.status, 413);
  });

  it('serves photos only through signed, expiring URLs', async () => {
    const view = await server.api('GET', '/api/v1/kyc/documents/selfie', { token });
    const signedUrl = new URL(view.body.data.document.url);
    const local = `${server.baseUrl}${signedUrl.pathname}`;

    const image = await fetch(local);
    assert.equal(image.status, 200);
    assert.equal(image.headers.get('content-type'), 'image/png');

    const tampered = await fetch(`${local.slice(0, -3)}abc`);
    assert.equal(tampered.status, 403);
  });

  it('full flow: multipart submit -> review -> approved', async () => {
    const form = imageForm('idFront', JPEG, completeDetails());
    form.append('idBack', new Blob([new Uint8Array(JPEG)]), 'back.jpg');
    const submit = await server.api('POST', '/api/v1/kyc/submit', { token, form });
    assert.equal(submit.status, 202, JSON.stringify(submit.body));
    assert.equal(submit.body.data.application.status, 'SUBMITTED');

    await context.worker.tick();
    const status = await server.api('GET', '/api/v1/kyc/status', { token });
    assert.equal(status.body.data.status, 'APPROVED');

    const locked = await server.api('PUT', '/api/v1/kyc/draft', { token, json: { city: 'Hanoi' } });
    assert.equal(locked.status, 409);
    assert.equal(locked.body.error.code, 'KYC_NOT_EDITABLE');
  });

  it('refresh rotation and logout over HTTP', async () => {
    const login = await server.api('POST', '/api/v1/auth/login', { json: { email: 'http@example.com', password: STRONG_PASSWORD } });
    const { refreshToken } = login.body.data.tokens;

    const refreshed = await server.api('POST', '/api/v1/auth/refresh', { json: { refreshToken } });
    assert.equal(refreshed.status, 200);
    const reused = await server.api('POST', '/api/v1/auth/refresh', { json: { refreshToken } });
    assert.equal(reused.status, 401);
    assert.equal(reused.body.error.code, 'REFRESH_TOKEN_REUSED');

    const logout = await server.api('POST', '/api/v1/auth/logout', { json: { refreshToken: refreshed.body.data.tokens.refreshToken } });
    assert.equal(logout.status, 204);
  });
});
