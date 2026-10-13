import type { PrismaClient } from '@prisma/client';
import type { Env } from './config/env';
import type { Logger } from './config/logger';
import { AuthController } from './controllers/auth.controller';
import { FilesController } from './controllers/files.controller';
import { KycController } from './controllers/kyc.controller';
import { createPrismaClient } from './database/prisma';
import { KycReviewWorker } from './jobs/kyc-review.worker';
import { KycRepository } from './repositories/kyc.repository';
import { RefreshTokenRepository } from './repositories/refresh-token.repository';
import { UserRepository } from './repositories/user.repository';
import { AuthService } from './services/auth.service';
import { KycAutoReviewer } from './services/kyc-reviewer.service';
import { KycService } from './services/kyc.service';
import { TokenService } from './services/token.service';
import { LocalStorageProvider, createStorageProvider } from './storage';
import type { StorageProvider } from './storage/storage.provider';

/** Runtime-specific infrastructure (e.g. Cloudflare Workers: Prisma on D1, storage on R2). */
export interface ContainerOverrides {
  prisma?: PrismaClient;
  storage?: StorageProvider;
}

/**
 * Composition root: the only place where concrete implementations are wired together
 * (manual constructor injection - easy to swap repositories/storage in tests).
 * `overrides` lets another runtime (Cloudflare Workers) supply its own database client and storage.
 */
export function createContainer(env: Env, logger: Logger, overrides: ContainerOverrides = {}) {
  const prisma = overrides.prisma ?? createPrismaClient(env);
  const storage = overrides.storage ?? createStorageProvider(env);

  const repositories = {
    users: new UserRepository(prisma),
    refreshTokens: new RefreshTokenRepository(prisma),
    kyc: new KycRepository(prisma),
  };

  const tokens = new TokenService({
    accessSecret: env.JWT_ACCESS_SECRET,
    refreshSecret: env.JWT_REFRESH_SECRET,
    accessTtlSeconds: env.JWT_ACCESS_TTL_SECONDS,
    refreshTtlSeconds: env.JWT_REFRESH_TTL_SECONDS,
    issuer: env.JWT_ISSUER,
    audience: env.JWT_AUDIENCE,
  });

  const services = {
    tokens,
    auth: new AuthService(repositories.users, repositories.refreshTokens, tokens, logger, {
      bcryptRounds: env.BCRYPT_SALT_ROUNDS,
    }),
    kyc: new KycService(repositories.kyc, storage, logger, {
      keyPrefix: env.STORAGE_KEY_PREFIX,
      downloadTtlSeconds: env.PRESIGNED_DOWNLOAD_TTL_SECONDS,
      uploadTtlSeconds: env.PRESIGNED_UPLOAD_TTL_SECONDS,
      maxUploadBytes: env.MAX_UPLOAD_SIZE_BYTES,
    }),
  };

  const reviewWorker = new KycReviewWorker(repositories.kyc, new KycAutoReviewer(env.KYC_AUTO_REVIEW_MODE), logger, {
    decisionDelayMs: env.KYC_AUTO_REVIEW_DELAY_MS,
    pollIntervalMs: env.KYC_REVIEW_POLL_INTERVAL_MS,
    batchSize: 25,
  });

  const controllers = {
    auth: new AuthController(services.auth),
    kyc: new KycController(services.kyc),
    files: storage instanceof LocalStorageProvider ? new FilesController(storage, env.MAX_UPLOAD_SIZE_BYTES) : null,
  };

  return { env, logger, prisma, storage, repositories, services, controllers, reviewWorker };
}

export type Container = ReturnType<typeof createContainer>;
