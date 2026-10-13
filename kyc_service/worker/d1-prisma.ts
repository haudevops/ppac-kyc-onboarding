import { PrismaD1 } from '@prisma/adapter-d1';
import { PrismaClient } from '@prisma/client';

/**
 * Prisma Client on Cloudflare D1.
 *
 * D1 has no interactive transactions, and Prisma's D1 adapter rejects `$transaction(async (tx) => ...)`.
 * The repositories use that form in four places (status transition + audit row, refresh-token rotation,
 * document upsert, document removal). Here the callback simply runs its statements one after another
 * on the same client, so the repositories stay unchanged:
 *  - race safety is kept: every guarded write is still a conditional UPDATE (`WHERE status = ?`,
 *    `WHERE revokedAt IS NULL`) whose row count decides the outcome;
 *  - what is lost is all-or-nothing atomicity: if the Worker died between two statements, a status change
 *    could lack its history row (see README "Cloudflare: trade-offs").
 * Batch transactions (`$transaction([...])`) are passed through unchanged.
 */
export function createD1PrismaClient(db: D1Database): PrismaClient {
  const client = new PrismaClient({ adapter: new PrismaD1(db) });

  return new Proxy(client, {
    get(target, prop, receiver) {
      if (prop === '$transaction') {
        return (arg: unknown, options?: unknown) =>
          typeof arg === 'function'
            ? (arg as (tx: PrismaClient) => Promise<unknown>)(receiver as PrismaClient)
            : (target.$transaction as (a: unknown, o?: unknown) => Promise<unknown>)(arg, options);
      }
      return Reflect.get(target, prop, receiver);
    },
  });
}
