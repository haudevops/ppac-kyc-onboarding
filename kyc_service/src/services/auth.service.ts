import { Prisma, type User } from '@prisma/client';
import { compare, hash } from 'bcryptjs';
import type { Logger } from '../config/logger';
import { type PublicUser, toPublicUser } from '../models/user.model';
import type { NewRefreshToken, RefreshTokenRepository } from '../repositories/refresh-token.repository';
import type { UserRepository } from '../repositories/user.repository';
import { newId, safeEqual, sha256Hex } from '../utils/crypto';
import { AppError, Errors } from '../utils/errors';
import type { ClientContext } from '../utils/http';
import type { LoginInput, RegisterInput } from '../validators/auth.schema';
import type { TokenService } from './token.service';

export interface AuthTokens {
  tokenType: 'Bearer';
  accessToken: string;
  /** Seconds until the access token expires. */
  expiresIn: number;
  refreshToken: string;
  refreshExpiresIn: number;
}

export interface AuthResult {
  user: PublicUser;
  tokens: AuthTokens;
}

export class AuthService {
  /** Used to keep login timing identical whether or not the email exists (prevents user enumeration). */
  private dummyHash?: Promise<string>;

  constructor(
    private readonly users: UserRepository,
    private readonly refreshTokens: RefreshTokenRepository,
    private readonly tokens: TokenService,
    private readonly logger: Logger,
    private readonly config: { bcryptRounds: number },
  ) {}

  async register(input: RegisterInput, ctx: ClientContext): Promise<AuthResult> {
    if (await this.users.findByEmail(input.email)) {
      throw Errors.conflict('An account with this email already exists', 'EMAIL_ALREADY_REGISTERED');
    }

    const passwordHash = await hash(input.password, this.config.bcryptRounds);
    let user: User;
    try {
      user = await this.users.create({ email: input.email, passwordHash, fullName: input.fullName ?? null });
    } catch (err) {
      // Lost a race with a concurrent registration for the same email.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw Errors.conflict('An account with this email already exists', 'EMAIL_ALREADY_REGISTERED');
      }
      throw err;
    }

    return { user: toPublicUser(user), tokens: await this.startSession(user, ctx) };
  }

  async login(input: LoginInput, ctx: ClientContext): Promise<AuthResult> {
    const user = await this.users.findByEmail(input.email);
    const passwordHash = user?.passwordHash ?? (await this.getDummyHash());
    const valid = await compare(input.password, passwordHash);

    if (!user || !valid) throw Errors.unauthorized('Invalid email or password', 'INVALID_CREDENTIALS');
    return { user: toPublicUser(user), tokens: await this.startSession(user, ctx) };
  }

  /**
   * Refresh-token rotation with reuse detection:
   *  - every refresh revokes the presented token and issues a new one in the same family;
   *  - presenting an already-revoked token means it was stolen/replayed, so the whole
   *    family (that login session on every device holding it) is revoked.
   */
  async refresh(refreshToken: string, ctx: ClientContext): Promise<AuthTokens> {
    const claims = this.tokens.verifyRefreshToken(refreshToken);
    const stored = await this.refreshTokens.findById(claims.jti);

    if (!stored || stored.userId !== claims.userId || !safeEqual(stored.tokenHash, sha256Hex(refreshToken))) {
      throw Errors.unauthorized('Invalid refresh token', 'INVALID_REFRESH_TOKEN');
    }
    if (stored.revokedAt) {
      await this.handleReuse(stored.familyId, stored.userId);
    }
    if (stored.expiresAt.getTime() <= Date.now()) {
      throw Errors.unauthorized('Refresh token expired', 'TOKEN_EXPIRED');
    }

    const user = await this.users.findById(stored.userId);
    if (!user) throw Errors.unauthorized('Invalid refresh token', 'INVALID_REFRESH_TOKEN');

    const next = this.buildRefreshToken(user.id, stored.familyId, ctx);
    const rotated = await this.refreshTokens.rotate(stored.id, next.record);
    if (!rotated) {
      // Another request rotated this token between our read and write: treat as reuse.
      await this.handleReuse(stored.familyId, stored.userId);
    }

    return this.toTokens(user, next.token);
  }

  /** Idempotent: always succeeds, even for unknown/expired tokens. Revokes the whole session family. */
  async logout(refreshToken: string): Promise<void> {
    let jti: string;
    try {
      jti = this.tokens.verifyRefreshToken(refreshToken, { ignoreExpiration: true }).jti;
    } catch {
      return;
    }
    const stored = await this.refreshTokens.findById(jti);
    if (stored && safeEqual(stored.tokenHash, sha256Hex(refreshToken))) {
      await this.refreshTokens.revokeFamily(stored.familyId);
    }
  }

  async me(userId: string): Promise<PublicUser> {
    const user = await this.users.findById(userId);
    if (!user) throw Errors.notFound('User not found');
    return toPublicUser(user);
  }

  /* ---------------------------------------------------------------- */

  private async startSession(user: User, ctx: ClientContext): Promise<AuthTokens> {
    const { token, record } = this.buildRefreshToken(user.id, newId(), ctx);
    await this.refreshTokens.create(record);
    return this.toTokens(user, token);
  }

  private buildRefreshToken(userId: string, familyId: string, ctx: ClientContext) {
    const jti = newId();
    const token = this.tokens.signRefreshToken({ userId, jti, familyId });
    const record: NewRefreshToken = {
      id: jti,
      userId,
      familyId,
      tokenHash: sha256Hex(token),
      expiresAt: new Date(Date.now() + this.tokens.refreshTtlSeconds * 1000),
      userAgent: ctx.userAgent ?? null,
      ip: ctx.ip ?? null,
    };
    return { token, record };
  }

  private toTokens(user: User, refreshToken: string): AuthTokens {
    return {
      tokenType: 'Bearer',
      accessToken: this.tokens.signAccessToken({ id: user.id, email: user.email }),
      expiresIn: this.tokens.accessTtlSeconds,
      refreshToken,
      refreshExpiresIn: this.tokens.refreshTtlSeconds,
    };
  }

  private async handleReuse(familyId: string, userId: string): Promise<never> {
    const revoked = await this.refreshTokens.revokeFamily(familyId);
    this.logger.warn('Refresh token reuse detected - session family revoked', { userId, familyId, revoked });
    throw new AppError(401, 'REFRESH_TOKEN_REUSED', 'Refresh token has already been used. Please log in again.');
  }

  private getDummyHash(): Promise<string> {
    const pending = this.dummyHash ?? hash('dummy-password-for-timing', this.config.bcryptRounds);
    this.dummyHash = pending;
    return pending;
  }
}
