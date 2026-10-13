/**
 * Cloudflare Workers entry point.
 *
 * The same Express app, controllers, services, repositories and validation as the Node server
 * (src/server.ts) - only the infrastructure is swapped:
 *   - HTTP:     Express runs on the Workers `node:http` support (httpServerHandler);
 *   - Database: Prisma Client on D1 through @prisma/adapter-d1 (binding DB, see d1-prisma.ts);
 *   - Storage:  R2StorageProvider - R2 bucket (binding FILES) + the usual signed /api/v1/files/:token URLs;
 *   - Review:   the existing KycReviewWorker.tick(), driven by a Durable Object alarm instead of setInterval.
 */
import http from 'node:http';
import { httpServerHandler } from 'cloudflare:node';
import { DurableObject, env as bindings } from 'cloudflare:workers';
import type { Express } from 'express';
import { createApp } from '../src/app';
import { env } from '../src/config/env';
import { logger } from '../src/config/logger';
import { type Container, createContainer } from '../src/container';
import { LOCAL_FILES_ROUTE } from '../src/storage';
import { R2StorageProvider } from '../src/storage/r2.storage';
import { createD1PrismaClient } from './d1-prisma';

/* ------------------------------------------------------------------ */
/* Composition (lazy: bindings are only usable inside a request)       */
/* ------------------------------------------------------------------ */

let container: Container | null = null;

function getContainer(): Container {
  if (!container) {
    const prisma = createD1PrismaClient(bindings.DB);
    const storage = new R2StorageProvider(bindings.FILES, {
      signingSecret: env.LOCAL_STORAGE_SIGNING_SECRET as string, // required by the env schema (STORAGE_DRIVER=local)
      filesBaseUrl: `${env.PUBLIC_BASE_URL}${LOCAL_FILES_ROUTE}`,
    });
    container = createContainer(env, logger, { prisma, storage });
  }
  return container;
}

let app: Express | null = null;
const server = http.createServer((req, res) => {
  app ??= createApp(getContainer());
  app(req, res);
});
server.listen(8080); // routing key for httpServerHandler, not a real port
const express = httpServerHandler({ port: 8080 });

/* ------------------------------------------------------------------ */
/* Simulated review: Durable Object alarm instead of setInterval        */
/* ------------------------------------------------------------------ */

const SUBMIT_PATH = '/api/v1/kyc/submit';

async function scheduleReview(): Promise<void> {
  if (!env.KYC_REVIEW_WORKER_ENABLED) return;
  const stub = bindings.REVIEW_SCHEDULER.get(bindings.REVIEW_SCHEDULER.idFromName('kyc-review'));
  await stub.ensureScheduled();
}

/**
 * One instance for the whole service. While applications are SUBMITTED or PROCESSING, its alarm fires
 * every KYC_REVIEW_POLL_INTERVAL_MS and runs one cycle of the existing review worker (pick up, then decide
 * once submittedAt + KYC_AUTO_REVIEW_DELAY_MS has passed). It goes idle when nothing is pending.
 */
export class KycReviewScheduler extends DurableObject {
  async ensureScheduled(): Promise<void> {
    if ((await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + 1000);
  }

  override async alarm(): Promise<void> {
    if (!env.KYC_REVIEW_WORKER_ENABLED) return;
    const c = getContainer();
    await c.reviewWorker.tick();

    const [submitted, processing] = await Promise.all([
      c.repositories.kyc.findIdsByStatus('SUBMITTED', 1),
      c.repositories.kyc.findIdsByStatus('PROCESSING', 1),
    ]);
    if (submitted.length > 0 || processing.length > 0) {
      await this.ctx.storage.setAlarm(Date.now() + env.KYC_REVIEW_POLL_INTERVAL_MS);
    }
  }
}

/* ------------------------------------------------------------------ */
/* Worker handlers                                                      */
/* ------------------------------------------------------------------ */

export default {
  async fetch(request: Request, cfEnv: Env, ctx: ExecutionContext): Promise<Response> {
    // Express reads the client IP from X-Forwarded-For (TRUST_PROXY=true): set it from Cloudflare's
    // own header so it cannot be spoofed by the client (used by the auth rate limiter).
    const headers = new Headers(request.headers);
    headers.set('x-forwarded-for', request.headers.get('cf-connecting-ip') ?? '127.0.0.1');
    const forwarded = new Request(request, { headers }) as Request<unknown, IncomingRequestCfProperties>;

    const response = await express.fetch!(forwarded, cfEnv, ctx);

    if (request.method === 'POST' && new URL(request.url).pathname === SUBMIT_PATH && response.status === 202) {
      ctx.waitUntil(scheduleReview());
    }
    return response;
  },

  /** Safety net (every minute): resumes reviews if an alarm was ever missed, e.g. after a deploy. */
  async scheduled(_controller: ScheduledController, _cfEnv: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(scheduleReview());
  },
} satisfies ExportedHandler<Env>;
