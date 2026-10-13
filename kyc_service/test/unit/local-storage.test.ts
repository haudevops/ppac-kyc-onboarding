import '../helpers/test-env';

import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { LocalStorageProvider } from '../../src/storage/local.storage';
import { AppError } from '../../src/utils/errors';
import { PNG } from '../helpers/fixtures';

const storage = new LocalStorageProvider({
  rootDir: mkdtempSync(path.join(tmpdir(), 'kyc-local-')),
  signingSecret: 'unit-test-signing-secret-0123456789-abcdef',
  filesBaseUrl: 'http://localhost:3000/api/v1/files',
});
const tokenOf = (url: string) => url.split('/').pop() as string;
const isForbidden = (e: unknown) => e instanceof AppError && e.statusCode === 403;

describe('LocalStorageProvider', () => {
  const key = 'kyc/user-1/app-1/selfie-abc.png';

  it('stores objects with metadata and reads them back', async () => {
    await storage.putObject({ key, body: PNG, contentType: 'image/png' });
    assert.deepEqual(await storage.getObjectMetadata(key), { contentType: 'image/png', contentLength: PNG.length });
    assert.deepEqual(await storage.readObjectPrefix(key, 8), PNG.subarray(0, 8));
  });

  it('signed download URLs work only for GET and cannot be tampered with', async () => {
    const { url } = await storage.createPresignedDownloadUrl(key, 60);
    const token = tokenOf(url);
    assert.equal(storage.verifyToken(token, 'get').key, key);
    assert.throws(() => storage.verifyToken(token, 'put'), isForbidden);

    // Change the payload (try to point at another user's file) but keep the signature.
    const [payload, signature] = token.split('.');
    const forged = Buffer.from(
      Buffer.from(payload, 'base64url').toString().replace('user-1', 'user-2'),
    ).toString('base64url');
    assert.throws(() => storage.verifyToken(`${forged}.${signature}`, 'get'), isForbidden);
  });

  it('signed URLs expire', async () => {
    const { url } = await storage.createPresignedDownloadUrl(key, -1);
    assert.throws(() => storage.verifyToken(tokenOf(url), 'get'), isForbidden);
  });

  it('upload URLs carry the content type that must be used', async () => {
    const upload = await storage.createPresignedUploadUrl({ key, contentType: 'image/png', ttlSeconds: 60 });
    assert.equal(upload.method, 'PUT');
    assert.deepEqual(upload.headers, { 'Content-Type': 'image/png' });
    assert.equal(storage.verifyToken(tokenOf(upload.url), 'put').contentType, 'image/png');
  });

  it('rejects path traversal and unsafe keys', async () => {
    for (const bad of ['../etc/passwd', 'kyc/../../secret', '/absolute', 'kyc/a.png.meta.json']) {
      await assert.rejects(() => storage.createPresignedDownloadUrl(bad, 60), AppError, bad);
    }
  });

  it('deletes objects and their metadata', async () => {
    await storage.deleteObject(key);
    assert.equal(await storage.getObjectMetadata(key), null);
  });
});
