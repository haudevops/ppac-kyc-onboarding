/* eslint-disable no-console */
import { env } from './env';

/**
 * Minimal structured logger (JSON in production, readable lines in development).
 * Never pass request bodies or PII into `meta`.
 */
type Level = 'debug' | 'info' | 'warn' | 'error';
type Meta = Record<string, unknown>;

const LEVEL_ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

function serialize(meta: Meta): Meta {
  const out: Meta = {};
  for (const [key, value] of Object.entries(meta)) {
    out[key] =
      value instanceof Error
        ? { name: value.name, message: value.message, stack: env.isProduction ? undefined : value.stack }
        : value;
  }
  return out;
}

function write(level: Level, message: string, meta: Meta = {}) {
  if (LEVEL_ORDER[level] < LEVEL_ORDER[env.LOG_LEVEL]) return;
  const time = new Date().toISOString();
  const data = serialize(meta);
  const sink = level === 'error' ? console.error : level === 'warn' ? console.warn : console.log;

  if (env.isProduction) {
    sink(JSON.stringify({ level, time, msg: message, ...data }));
  } else {
    const extra = Object.keys(data).length ? ` ${JSON.stringify(data)}` : '';
    sink(`[${time}] ${level.toUpperCase().padEnd(5)} ${message}${extra}`);
  }
}

export const logger = {
  debug: (message: string, meta?: Meta) => write('debug', message, meta),
  info: (message: string, meta?: Meta) => write('info', message, meta),
  warn: (message: string, meta?: Meta) => write('warn', message, meta),
  error: (message: string, meta?: Meta) => write('error', message, meta),
};

export type Logger = typeof logger;
