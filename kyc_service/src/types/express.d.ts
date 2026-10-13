import type { AuthUser } from '../models/user.model';

declare global {
  namespace Express {
    interface Request {
      /** Set by the request-id middleware on every request. */
      requestId: string;
      /** Set by the `authenticate` middleware. */
      user?: AuthUser;
    }
  }
}

export {};
