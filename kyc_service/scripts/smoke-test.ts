/**
 * End-to-end smoke test against a running server:  npm run smoke
 * (optionally API_URL=http://host:port npm run smoke)
 *
 * Runs three applicants in parallel through the whole flow (backend in KYC_AUTO_REVIEW_MODE=rule):
 *  - "Alice Nguyen"  -> APPROVED
 *  - "Reject Tester" -> REJECTED (final: editing is refused afterwards)
 *  - "Retake Tester" -> RESUBMISSION_REQUESTED (selfie) -> new selfie + resubmit -> APPROVED
 * and exercises refresh-token rotation, reuse detection and logout.
 */
import assert from 'node:assert/strict';

const BASE = (process.env.API_URL ?? 'http://localhost:3000').replace(/\/+$/, '');
const API = `${BASE}/api/v1`;

// 1x1 transparent PNG (valid magic bytes)
const PNG = new Uint8Array(
  Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    'base64',
  ),
);

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

interface CallOptions {
  token?: string;
  json?: unknown;
  form?: FormData;
}

async function call(method: string, path: string, opts: CallOptions = {}): Promise<{ status: number; body: Json }> {
  const headers: Record<string, string> = {};
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  let body: string | FormData | undefined;
  if (opts.json !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(opts.json);
  } else if (opts.form) {
    body = opts.form;
  }
  const res = await fetch(`${API}${path}`, { method, headers, body });
  const text = await res.text();
  return { status: res.status, body: text ? (JSON.parse(text) as Json) : {} };
}

function expectStatus(label: string, actual: { status: number; body: Json }, expected: number) {
  if (actual.status !== expected) {
    console.error(`✗ ${label}: expected HTTP ${expected}, got ${actual.status}`, JSON.stringify(actual.body, null, 2));
    process.exit(1);
  }
  console.log(`✓ ${label} (${actual.status})`);
}

const pngForm = (field: string, extra: Record<string, string> = {}) => {
  const form = new FormData();
  form.append(field, new Blob([PNG], { type: 'image/png' }), `${field}.png`);
  for (const [k, v] of Object.entries(extra)) form.append(k, v);
  return form;
};

const isoDateFromNow = (years: number) => {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() + years);
  return d.toISOString().slice(0, 10);
};

type Outcome = 'APPROVED' | 'REJECTED' | 'RESUBMISSION_REQUESTED';

async function waitForDecision(tag: string, token: string): Promise<string> {
  const started = Date.now();
  let status = 'SUBMITTED';
  const seen = new Set<string>([status]);
  while (['SUBMITTED', 'PROCESSING'].includes(status)) {
    if (Date.now() - started > 30_000) throw new Error(`${tag} timed out waiting for review (last: ${status})`);
    await new Promise((r) => setTimeout(r, 1000));
    status = (await call('GET', '/kyc/status', { token })).body.data.status;
    seen.add(status);
  }
  console.log(`✓ ${tag} ${[...seen].join(' -> ')} after ${((Date.now() - started) / 1000).toFixed(1)}s`);
  return status;
}

async function runApplicant(fullName: string, expected: Outcome) {
  const tag = `[${fullName}]`;
  const email = `smoke+${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.com`;
  const password = 'Sup3rSecret!';

  const reg = await call('POST', '/auth/register', { json: { email, password, fullName } });
  expectStatus(`${tag} register`, reg, 201);
  const token: string = reg.body.data.tokens.accessToken;

  const initial = await call('GET', '/kyc', { token });
  expectStatus(`${tag} GET /kyc`, initial, 200);
  assert.equal(initial.body.data.status, 'NOT_STARTED');

  const draft = await call('PUT', '/kyc/draft', {
    token,
    json: { fullName, dateOfBirth: '1990-05-20', nationality: 'vn', currentStep: 'PERSONAL_INFO' },
  });
  expectStatus(`${tag} save draft`, draft, 200);
  assert.equal(draft.body.data.application.status, 'DRAFT');
  assert.equal(draft.body.data.application.personalDetails.nationality, 'VN');

  const invalid = await call('PUT', '/kyc/draft', { token, json: { dateOfBirth: '2020-13-45' } });
  expectStatus(`${tag} invalid draft rejected`, invalid, 400);

  const early = await call('POST', '/kyc/submit', { token, json: {} });
  expectStatus(`${tag} incomplete submit -> KYC_INCOMPLETE`, early, 422);
  assert.equal(early.body.error.code, 'KYC_INCOMPLETE');

  // Option A: multipart upload through the API
  const front = await call('POST', '/kyc/documents/id-front', { token, form: pngForm('file') });
  expectStatus(`${tag} upload ID_FRONT (multipart)`, front, 201);

  // Option B: presigned URL -> PUT directly to storage -> confirm
  const ticket = await call('POST', '/kyc/documents/id-back/upload-url', {
    token,
    json: { contentType: 'image/png', contentLength: PNG.length },
  });
  expectStatus(`${tag} create presigned upload URL`, ticket, 201);
  const upload = ticket.body.data.upload;
  const put = await fetch(upload.url, { method: 'PUT', headers: upload.headers, body: PNG });
  assert.ok(put.ok, `${tag} presigned PUT failed with ${put.status}: ${await put.text()}`);
  console.log(`✓ ${tag} PUT to presigned URL (${put.status})`);
  const confirm = await call('POST', '/kyc/documents/id-back/confirm', { token, json: { key: upload.key } });
  expectStatus(`${tag} confirm presigned upload`, confirm, 200);

  // Remaining details + selfie in a single multipart submit
  const submit = await call('POST', '/kyc/submit', {
    token,
    form: pngForm('selfie', {
      addressLine1: '12 Nguyen Hue',
      city: 'Ho Chi Minh City',
      country: 'VN',
      idType: 'NATIONAL_ID',
      idNumber: '079090001234',
      idIssueDate: '2021-01-15',
      idExpiryDate: isoDateFromNow(5),
    }),
  });
  expectStatus(`${tag} submit`, submit, 202);
  assert.equal(submit.body.data.application.status, 'SUBMITTED');
  assert.match(submit.body.data.application.personalDetails.idNumber, /^\*+1234$/, 'ID number must be masked');

  const locked = await call('PUT', '/kyc/draft', { token, json: { city: 'Hanoi' } });
  expectStatus(`${tag} edit after submit -> KYC_NOT_EDITABLE`, locked, 409);

  // Poll until the simulated reviewer decides (~10s)
  const status = await waitForDecision(tag, token);
  assert.equal(status, expected);

  const full = await call('GET', '/kyc', { token });
  expectStatus(`${tag} GET /kyc (final)`, full, 200);
  const doc = full.body.data.application.documents[0];
  const image = await fetch(doc.url);
  assert.ok(image.ok, `${tag} presigned GET failed with ${image.status}`);
  console.log(`✓ ${tag} presigned download ${doc.type} (${image.headers.get('content-type')})`);

  if (expected === 'REJECTED') {
    assert.ok(full.body.data.application.rejectionReason, 'rejectionReason expected');
    const edit = await call('PUT', '/kyc/draft', { token, json: { city: 'Hanoi' } });
    expectStatus(`${tag} rejection is final -> KYC_NOT_EDITABLE`, edit, 409);
  }

  if (expected === 'RESUBMISSION_REQUESTED') {
    assert.deepEqual(full.body.data.application.resubmissionItems, ['SELFIE']);
    const selfie = await call('POST', '/kyc/documents/selfie', { token, form: pngForm('file') });
    expectStatus(`${tag} retake requested selfie (re-opens the application)`, selfie, 201);
    const resubmit = await call('POST', '/kyc/submit', { token, json: {} });
    expectStatus(`${tag} resubmit`, resubmit, 202);
    assert.equal(await waitForDecision(tag, token), 'APPROVED');
  }

  return { email, password, refreshToken: reg.body.data.tokens.refreshToken as string };
}

async function authFlows(email: string, password: string, firstRefreshToken: string) {
  const rotated = await call('POST', '/auth/refresh', { json: { refreshToken: firstRefreshToken } });
  expectStatus('[auth] refresh rotates token', rotated, 200);

  const reused = await call('POST', '/auth/refresh', { json: { refreshToken: firstRefreshToken } });
  expectStatus('[auth] reusing old refresh token -> REFRESH_TOKEN_REUSED', reused, 401);
  assert.equal(reused.body.error.code, 'REFRESH_TOKEN_REUSED');

  const familyRevoked = await call('POST', '/auth/refresh', { json: { refreshToken: rotated.body.data.tokens.refreshToken } });
  expectStatus('[auth] whole session family revoked after reuse', familyRevoked, 401);

  const badLogin = await call('POST', '/auth/login', { json: { email, password: 'wrong-Passw0rd' } });
  expectStatus('[auth] wrong password', badLogin, 401);

  const login = await call('POST', '/auth/login', { json: { email, password } });
  expectStatus('[auth] login', login, 200);
  const { accessToken, refreshToken } = login.body.data.tokens;

  expectStatus('[auth] GET /auth/me', await call('GET', '/auth/me', { token: accessToken }), 200);
  expectStatus('[auth] no token -> 401', await call('GET', '/kyc'), 401);

  expectStatus('[auth] logout', await call('POST', '/auth/logout', { json: { refreshToken } }), 204);
  expectStatus('[auth] refresh after logout -> 401', await call('POST', '/auth/refresh', { json: { refreshToken } }), 401);
}

async function main() {
  console.log(`Smoke testing ${BASE}\n`);
  const health = await fetch(`${BASE}/health`).catch(() => null);
  if (!health?.ok) {
    console.error(`Server is not reachable at ${BASE} - start it with "npm run dev" first.`);
    process.exit(1);
  }

  const [alice] = await Promise.all([
    runApplicant('Alice Nguyen', 'APPROVED'),
    runApplicant('Reject Tester', 'REJECTED'),
    runApplicant('Retake Tester', 'RESUBMISSION_REQUESTED'),
  ]);
  await authFlows(alice.email, alice.password, alice.refreshToken);

  console.log('\nAll smoke checks passed ✅');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
