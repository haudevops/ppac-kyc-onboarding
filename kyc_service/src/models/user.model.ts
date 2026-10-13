import type { User } from '@prisma/client';

/** Identity attached to an authenticated request (from the access token). */
export interface AuthUser {
  id: string;
  email: string;
}

/** User shape that is safe to return to clients (no password hash). */
export interface PublicUser {
  id: string;
  email: string;
  fullName: string | null;
  createdAt: Date;
}

export const toPublicUser = (user: User): PublicUser => ({
  id: user.id,
  email: user.email,
  fullName: user.fullName,
  createdAt: user.createdAt,
});
