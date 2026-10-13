import type { ZodError } from 'zod';

export interface FieldIssue {
  field: string;
  message: string;
}

export function formatZodIssues(error: ZodError, location?: string): FieldIssue[] {
  return error.issues.map((issue) => {
    const path = issue.path.join('.');
    return {
      field: [location, path].filter(Boolean).join('.') || '(root)',
      message: issue.message,
    };
  });
}
