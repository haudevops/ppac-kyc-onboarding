import type { PrismaClient, RefreshToken } from '@prisma/client';

export interface NewRefreshToken {
  id: string;
  userId: string;
  familyId: string;
  tokenHash: string;
  expiresAt: Date;
  userAgent?: string | null;
  ip?: string | null;
}

export class RefreshTokenRepository {
  constructor(private readonly db: PrismaClient) {}

  findById(id: string): Promise<RefreshToken | null> {
    return this.db.refreshToken.findUnique({ where: { id } });
  }

  async create(token: NewRefreshToken): Promise<void> {
    await this.db.refreshToken.create({ data: token });
  }

  /**
   * Atomically revokes `oldId` and stores its replacement.
   * Returns false if `oldId` was already revoked (concurrent refresh / token reuse).
   */
  rotate(oldId: string, replacement: NewRefreshToken): Promise<boolean> {
    return this.db.$transaction(async (tx) => {
      const { count } = await tx.refreshToken.updateMany({
        where: { id: oldId, revokedAt: null },
        data: { revokedAt: new Date(), replacedById: replacement.id },
      });
      if (count === 0) return false;
      await tx.refreshToken.create({ data: replacement });
      return true;
    });
  }

  async revokeFamily(familyId: string): Promise<number> {
    const { count } = await this.db.refreshToken.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return count;
  }

  async deleteExpired(before: Date = new Date()): Promise<number> {
    const { count } = await this.db.refreshToken.deleteMany({ where: { expiresAt: { lt: before } } });
    return count;
  }
}
