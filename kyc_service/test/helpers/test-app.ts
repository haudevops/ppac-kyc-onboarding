import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createApp } from '../../src/app';
import { env } from '../../src/config/env';
import type { Logger } from '../../src/config/logger';
import type { Container } from '../../src/container';
import { AuthController } from '../../src/controllers/auth.controller';
import { FilesController } from '../../src/controllers/files.controller';
import { KycController } from '../../src/controllers/kyc.controller';
import { KycReviewWorker } from '../../src/jobs/kyc-review.worker';
import { AuthService } from '../../src/services/auth.service';
import { KycAutoReviewer, type ReviewMode } from '../../src/services/kyc-reviewer.service';
import { KycService } from '../../src/services/kyc.service';
import { TokenService } from '../../src/services/token.service';
import { LocalStorageProvider } from '../../src/storage/local.storage';
import { InMemoryKycRepository, InMemoryRefreshTokenRepository, InMemoryUserRepository } from './in-memory-repositories';

export const silentLogger: Logger = { debug: () => {}, info: () => {}, warn: () => {}, error: () => {} };

/** Wires the real services/controllers/routes on top of in-memory repositories. */
export function createTestContext(options: { reviewMode?: ReviewMode } = {}) {
  const users = new InMemoryUserRepository();
  const refreshTokens = new InMemoryRefreshTokenRepository();
  const kyc = new InMemoryKycRepository();
  const storage = new LocalStorageProvider({
    rootDir: env.LOCAL_STORAGE_DIR,
    signingSecret: env.LOCAL_STORAGE_SIGNING_SECRET as string,
    filesBaseUrl: `${env.PUBLIC_BASE_URL}/api/v1/files`,
  });

  const tokens = new TokenService({
    accessSecret: env.JWT_ACCESS_SECRET,
    refreshSecret: env.JWT_REFRESH_SECRET,
    accessTtlSeconds: env.JWT_ACCESS_TTL_SECONDS,
    refreshTtlSeconds: env.JWT_REFRESH_TTL_SECONDS,
    issuer: env.JWT_ISSUER,
    audience: env.JWT_AUDIENCE,
  });
  const auth = new AuthService(users.asRepository(), refreshTokens.asRepository(), tokens, silentLogger, {
    bcryptRounds: env.BCRYPT_SALT_ROUNDS,
  });
  const kycService = new KycService(kyc.asRepository(), storage, silentLogger, {
    keyPrefix: '',
    downloadTtlSeconds: 300,
    uploadTtlSeconds: 600,
    maxUploadBytes: env.MAX_UPLOAD_SIZE_BYTES,
  });
  const worker = new KycReviewWorker(
    kyc.asRepository(),
    new KycAutoReviewer(options.reviewMode ?? 'rule'),
    silentLogger,
    { decisionDelayMs: 0, pollIntervalMs: 60_000, batchSize: 25 },
  );

  const container = {
    env,
    logger: silentLogger,
    prisma: { $queryRawUnsafe: async () => [{ ok: 1 }] },
    storage,
    repositories: { users, refreshTokens, kyc },
    services: { tokens, auth, kyc: kycService },
    controllers: {
      auth: new AuthController(auth),
      kyc: new KycController(kycService),
      files: new FilesController(storage, env.MAX_UPLOAD_SIZE_BYTES),
    },
    reviewWorker: worker,
  } as unknown as Container;

  return { users, refreshTokens, kyc, storage, tokens, auth, kycService, worker, container };
}

/** Starts the Express app on a random port. */
export async function startServer(container: Container) {
  const server: Server = createApp(container).listen(0);
  await new Promise<void>((resolve) => server.once('listening', resolve));
  const { port } = server.address() as AddressInfo;
  const baseUrl = `http://127.0.0.1:${port}`;

  const api = async (method: string, path: string, opts: { token?: string; json?: unknown; form?: FormData } = {}) => {
    const headers: Record<string, string> = {};
    if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
    let body: string | FormData | undefined;
    if (opts.json !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(opts.json);
    } else if (opts.form) {
      body = opts.form;
    }
    const res = await fetch(`${baseUrl}${path}`, { method, headers, body });
    const text = await res.text();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const json = (text ? JSON.parse(text) : {}) as any;
    return { status: res.status, headers: res.headers, body: json };
  };

  const close = () => new Promise<void>((resolve) => server.close(() => resolve()));
  return { baseUrl, api, close };
}
