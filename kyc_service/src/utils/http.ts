import type { Request, Response } from 'express';

/** Uniform success envelope: `{ success: true, data }`. Errors use `{ success: false, error }`. */
export function sendOk<T>(res: Response, data: T, statusCode = 200): void {
  res.status(statusCode).json({ success: true, data });
}

export function sendNoContent(res: Response): void {
  res.status(204).end();
}

export interface ClientContext {
  userAgent?: string;
  ip?: string;
}

export function clientContext(req: Request): ClientContext {
  return {
    userAgent: req.get('user-agent')?.slice(0, 255),
    ip: req.ip,
  };
}

/** Reads values stored by the `validate` middleware. */
export function validated<T>(res: Response, part: 'body' | 'params' | 'query'): T {
  const store = res.locals.validated as Partial<Record<typeof part, unknown>> | undefined;
  return store?.[part] as T;
}
