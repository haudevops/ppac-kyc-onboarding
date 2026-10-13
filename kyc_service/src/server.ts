import type { Server } from 'node:http';
import { createApp } from './app';
import { env } from './config/env';
import { logger } from './config/logger';
import { createContainer } from './container';
import { connectDatabase } from './database/prisma';
import { LocalStorageProvider } from './storage';

const SHUTDOWN_TIMEOUT_MS = 10_000;

async function main(): Promise<void> {
  const container = createContainer(env, logger);

  await connectDatabase(container.prisma, env, logger);
  if (container.storage instanceof LocalStorageProvider) await container.storage.init();

  const app = createApp(container);
  const server: Server = app.listen(env.PORT);

  await new Promise<void>((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });

  logger.info(`KYC service listening on ${env.PUBLIC_BASE_URL}`, {
    env: env.NODE_ENV,
    storageDriver: container.storage.driver,
    devEndpoints: env.ENABLE_DEV_ENDPOINTS,
  });

  if (env.KYC_REVIEW_WORKER_ENABLED) container.reviewWorker.start();

  let shuttingDown = false;
  const shutdown = async (signal: string) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info(`${signal} received, shutting down gracefully`);

    const forceExit = setTimeout(() => {
      logger.error('Graceful shutdown timed out, forcing exit');
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS);
    forceExit.unref();

    try {
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await container.reviewWorker.stop();
      await container.prisma.$disconnect();
      process.exit(0);
    } catch (err) {
      logger.error('Error during shutdown', { err });
      process.exit(1);
    }
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled promise rejection', { err: reason instanceof Error ? reason : new Error(String(reason)) });
});

main().catch((err: unknown) => {
  logger.error('Failed to start server', { err: err instanceof Error ? err : new Error(String(err)) });
  process.exit(1);
});
