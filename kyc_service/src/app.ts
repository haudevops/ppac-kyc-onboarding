import cors from 'cors';
import express, { type Express } from 'express';
import helmet from 'helmet';
import type { Container } from './container';
import { errorHandler, notFoundHandler } from './middlewares/error.middleware';
import { requestId, requestLogger } from './middlewares/request-context.middleware';
import { buildApiRouter } from './routes';
import { sendOk } from './utils/http';

export function createApp(c: Container): Express {
  const app = express();
  const { env } = c;

  app.disable('x-powered-by');
  if (env.TRUST_PROXY) app.set('trust proxy', 1); // correct client IPs behind a load balancer (rate limiting)

  app.use(requestId);
  app.use(requestLogger(c.logger));
  app.use(
    helmet({
      // Allow the mobile/web app (different origin) to render images served by the local files route.
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );
  app.use(
    cors({
      origin: env.CORS_ORIGINS === '*' ? true : env.CORS_ORIGINS,
      exposedHeaders: ['X-Request-Id'],
      maxAge: 600,
    }),
  );
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', (_req, res) => {
    sendOk(res, { status: 'ok', uptimeSeconds: Math.round(process.uptime()), storageDriver: c.storage.driver });
  });
  app.get('/health/ready', async (_req, res) => {
    await c.prisma.$queryRawUnsafe('SELECT 1');
    sendOk(res, { status: 'ready' });
  });

  app.use('/api/v1', buildApiRouter(c));

  app.use(notFoundHandler);
  app.use(errorHandler(c.logger, !env.isProduction));

  return app;
}
