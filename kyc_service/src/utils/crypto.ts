import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto';

export const newId = (): string => randomUUID();

export function sha256Hex(input: string | Buffer): string {
  return createHash('sha256').update(input).digest('hex');
}

export function hmacSha256(secret: string, data: string): string {
  return createHmac('sha256', secret).update(data).digest('base64url');
}

/** Constant-time string comparison (avoids timing side channels on signatures / hashes). */
export function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}
