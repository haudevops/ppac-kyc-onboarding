import type { RequestHandler } from 'express';
import type { ZodTypeAny } from 'zod';
import { Errors } from '../utils/errors';
import { type FieldIssue, formatZodIssues } from '../utils/zod';

type RequestPart = 'params' | 'query' | 'body';
type Schemas = Partial<Record<RequestPart, ZodTypeAny>>;

/**
 * Validates and normalises request parts with Zod. All issues across parts are returned
 * together as a 400 VALIDATION_ERROR. Parsed values are stored in `res.locals.validated`
 * (Express 5 makes `req.query` read-only) and the parsed body also replaces `req.body`.
 */
export const validate =
  (schemas: Schemas): RequestHandler =>
  (req, res, next) => {
    const issues: FieldIssue[] = [];
    const parsed: Partial<Record<RequestPart, unknown>> = {};

    for (const part of ['params', 'query', 'body'] as const) {
      const schema = schemas[part];
      if (!schema) continue;
      const result = schema.safeParse(req[part] ?? {});
      if (result.success) parsed[part] = result.data;
      else issues.push(...formatZodIssues(result.error, part));
    }

    if (issues.length > 0) return next(Errors.validation(issues));

    res.locals.validated = { ...(res.locals.validated ?? {}), ...parsed };
    if ('body' in parsed) req.body = parsed.body;
    next();
  };
