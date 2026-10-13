/**
 * Must be the FIRST import of every test file: the config module validates process.env
 * as soon as it is loaded. Values set here win over `.env` (dotenv never overrides).
 */
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

Object.assign(process.env, {
  NODE_ENV: 'test',
  LOG_LEVEL: 'error',
  PORT: '3999', // unused: test servers listen on a random port
  PUBLIC_BASE_URL: 'http://localhost:3000',
  JWT_ACCESS_SECRET: 'test-access-secret-0123456789-abcdefghijklmnop',
  JWT_REFRESH_SECRET: 'test-refresh-secret-0123456789-abcdefghijklmnop',
  BCRYPT_SALT_ROUNDS: '8',
  AUTH_RATE_LIMIT_MAX: '10000',
  STORAGE_DRIVER: 'local',
  LOCAL_STORAGE_DIR: mkdtempSync(path.join(tmpdir(), 'kyc-test-storage-')),
  LOCAL_STORAGE_SIGNING_SECRET: 'test-local-signing-secret-0123456789-abcdef',
  STORAGE_KEY_PREFIX: '',
  KYC_REVIEW_WORKER_ENABLED: 'false',
  KYC_AUTO_REVIEW_DELAY_MS: '0',
  KYC_AUTO_REVIEW_MODE: 'rule',
  ENABLE_DEV_ENDPOINTS: 'true',
  MAX_UPLOAD_SIZE_MB: '1',
});
