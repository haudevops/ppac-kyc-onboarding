import type { PrismaClient, User } from '@prisma/client';

export class UserRepository {
  constructor(private readonly db: PrismaClient) {}

  findById(id: string): Promise<User | null> {
    return this.db.user.findUnique({ where: { id } });
  }

  findByEmail(email: string): Promise<User | null> {
    return this.db.user.findUnique({ where: { email } });
  }

  create(data: { email: string; passwordHash: string; fullName?: string | null }): Promise<User> {
    return this.db.user.create({ data });
  }
}
