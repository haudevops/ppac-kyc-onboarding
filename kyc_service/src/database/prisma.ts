import { PrismaClient } from '@prisma/client';
import type { Env } from '../config/env';
import type { Logger } from '../config/logger';

export function createPrismaClient(env: Env): PrismaClient {
  return new PrismaClient({
    // Tests trigger handled errors on purpose (e.g. unique-constraint races): keep their output clean.
    log: env.NODE_ENV === 'test' ? [] : env.isProduction ? ['error'] : ['warn', 'error'],
  });
}

/** Connects and applies SQLite pragmas that make concurrent API + worker writes safe. */
export async function connectDatabase(prisma: PrismaClient, env: Env, logger: Logger): Promise<void> {
  await prisma.$connect();

  if (env.DATABASE_URL.startsWith('file:')) {
    try {
      // PRAGMA statements return rows, so they must go through $queryRaw rather than $executeRaw.
      await prisma.$queryRawUnsafe('PRAGMA journal_mode = WAL;');
      await prisma.$queryRawUnsafe('PRAGMA busy_timeout = 5000;');
    } catch (err) {
      logger.warn('Could not apply SQLite pragmas', { err });
    }
  }
}
