import 'dotenv/config';
import { z } from 'zod';

/**
 * Centralised, validated configuration. The process refuses to start with an invalid config
 * instead of failing later at request time.
 */

const booleanFromEnv = (defaultValue: boolean) =>
  z
    .string()
    .optional()
    .transform((value) =>
      value === undefined ? defaultValue : ['true', '1', 'yes', 'on'].includes(value.trim().toLowerCase()),
    );

const INSECURE_SECRET_PREFIX = 'change-me';

const envSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(3000),
    PUBLIC_BASE_URL: z.string().url().default('http://localhost:3000'),
    CORS_ORIGINS: z.string().default('*'),
    TRUST_PROXY: booleanFromEnv(false),
    LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),

    DATABASE_URL: z.string().min(1).default('file:./dev.db?connection_limit=1'),

    JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET must be at least 32 characters'),
    JWT_REFRESH_SECRET: z.string().min(32, 'JWT_REFRESH_SECRET must be at least 32 characters'),
    JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(15 * 60),
    JWT_REFRESH_TTL_SECONDS: z.coerce.number().int().positive().default(30 * 24 * 60 * 60),
    JWT_ISSUER: z.string().min(1).default('kyc-service'),
    JWT_AUDIENCE: z.string().min(1).default('kyc-app'),
    BCRYPT_SALT_ROUNDS: z.coerce.number().int().min(8).max(15).default(12),

    AUTH_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(15 * 60 * 1000),
    AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().default(30),

    STORAGE_DRIVER: z.enum(['local', 's3']).default('local'),
    LOCAL_STORAGE_DIR: z.string().min(1).default('./storage'),
    LOCAL_STORAGE_SIGNING_SECRET: z.string().min(32).optional(),

    R2_ACCOUNT_ID: z.string().optional(),
    S3_ENDPOINT: z.string().url().optional(),
    S3_REGION: z.string().min(1).default('auto'),
    S3_BUCKET: z.string().optional(),
    S3_ACCESS_KEY_ID: z.string().optional(),
    S3_SECRET_ACCESS_KEY: z.string().optional(),
    S3_FORCE_PATH_STYLE: booleanFromEnv(true),
    STORAGE_KEY_PREFIX: z.string().default(''),

    PRESIGNED_DOWNLOAD_TTL_SECONDS: z.coerce.number().int().min(30).max(3600).default(300),
    PRESIGNED_UPLOAD_TTL_SECONDS: z.coerce.number().int().min(30).max(3600).default(600),
    MAX_UPLOAD_SIZE_MB: z.coerce.number().positive().max(25).default(5),

    KYC_REVIEW_WORKER_ENABLED: booleanFromEnv(true),
    KYC_AUTO_REVIEW_DELAY_MS: z.coerce.number().int().min(0).default(10_000),
    KYC_REVIEW_POLL_INTERVAL_MS: z.coerce.number().int().min(100).default(1_000),
    KYC_AUTO_REVIEW_MODE: z.enum(['rule', 'approve', 'reject', 'resubmit', 'random']).default('rule'),

    ENABLE_DEV_ENDPOINTS: z.string().optional(),
  })
  .superRefine((cfg, ctx) => {
    const issue = (path: string, message: string) => ctx.addIssue({ code: z.ZodIssueCode.custom, path: [path], message });

    if (cfg.STORAGE_DRIVER === 'local' && !cfg.LOCAL_STORAGE_SIGNING_SECRET) {
      issue('LOCAL_STORAGE_SIGNING_SECRET', 'Required when STORAGE_DRIVER=local (signs the local presigned URLs)');
    }

    if (cfg.STORAGE_DRIVER === 's3') {
      if (!cfg.S3_BUCKET) issue('S3_BUCKET', 'Required when STORAGE_DRIVER=s3');
      if (!cfg.S3_ACCESS_KEY_ID) issue('S3_ACCESS_KEY_ID', 'Required when STORAGE_DRIVER=s3');
      if (!cfg.S3_SECRET_ACCESS_KEY) issue('S3_SECRET_ACCESS_KEY', 'Required when STORAGE_DRIVER=s3');
      if (!cfg.S3_ENDPOINT && !cfg.R2_ACCOUNT_ID && cfg.S3_REGION === 'auto') {
        issue('S3_ENDPOINT', 'Set R2_ACCOUNT_ID (Cloudflare R2), S3_ENDPOINT (R2/MinIO) or a real S3_REGION (AWS S3)');
      }
    }

    if (cfg.NODE_ENV === 'production') {
      const secrets = ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'LOCAL_STORAGE_SIGNING_SECRET'] as const;
      for (const key of secrets) {
        if (cfg[key]?.startsWith(INSECURE_SECRET_PREFIX)) issue(key, 'Placeholder secret is not allowed in production');
      }
      if (cfg.JWT_ACCESS_SECRET === cfg.JWT_REFRESH_SECRET) {
        issue('JWT_REFRESH_SECRET', 'Must be different from JWT_ACCESS_SECRET');
      }
    }
  });

function loadEnv() {
  // Treat empty strings (e.g. `S3_ENDPOINT=`) as "not set".
  const raw = Object.fromEntries(Object.entries(process.env).filter(([, value]) => value !== ''));
  const result = envSchema.safeParse(raw);

  if (!result.success) {
    const lines = result.error.issues.map((i) => `  - ${i.path.join('.') || '(root)'}: ${i.message}`);
    // eslint-disable-next-line no-console
    console.error(`\n[config] Invalid environment configuration:\n${lines.join('\n')}\n\nSee .env.example\n`);
    process.exit(1);
    // Cloudflare Workers: process.exit() does not stop module evaluation - fail with the same details.
    throw new Error(`Invalid environment configuration:\n${lines.join('\n')}`);
  }

  const cfg = result.data;
  const isProduction = cfg.NODE_ENV === 'production';

  const s3Endpoint =
    cfg.S3_ENDPOINT ?? (cfg.R2_ACCOUNT_ID ? `https://${cfg.R2_ACCOUNT_ID}.r2.cloudflarestorage.com` : undefined);

  return {
    ...cfg,
    isProduction,
    PUBLIC_BASE_URL: cfg.PUBLIC_BASE_URL.replace(/\/+$/, ''),
    S3_ENDPOINT: s3Endpoint,
    STORAGE_KEY_PREFIX: normalizePrefix(cfg.STORAGE_KEY_PREFIX),
    MAX_UPLOAD_SIZE_BYTES: Math.floor(cfg.MAX_UPLOAD_SIZE_MB * 1024 * 1024),
    ENABLE_DEV_ENDPOINTS:
      cfg.ENABLE_DEV_ENDPOINTS === undefined ? !isProduction : cfg.ENABLE_DEV_ENDPOINTS.toLowerCase() === 'true',
    CORS_ORIGINS:
      cfg.CORS_ORIGINS.trim() === '*'
        ? ('*' as const)
        : cfg.CORS_ORIGINS.split(',')
            .map((o) => o.trim())
            .filter(Boolean),
  };
}

function normalizePrefix(prefix: string): string {
  const trimmed = prefix.trim().replace(/^\/+|\/+$/g, '');
  return trimmed ? `${trimmed}/` : '';
}

export const env = loadEnv();
export type Env = typeof env;
