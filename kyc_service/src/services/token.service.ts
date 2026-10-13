import { JsonWebTokenError, TokenExpiredError, sign, verify, type JwtPayload } from 'jsonwebtoken';
import type { AuthUser } from '../models/user.model';
import { Errors } from '../utils/errors';

export interface TokenServiceConfig {
  accessSecret: string;
  refreshSecret: string;
  accessTtlSeconds: number;
  refreshTtlSeconds: number;
  issuer: string;
  audience: string;
}

export interface RefreshTokenClaims {
  userId: string;
  jti: string;
  familyId: string;
}

/**
 * Pure JWT signing / verification. Persistence of refresh tokens lives in AuthService.
 *  - Access token : short-lived, stateless, sent as `Authorization: Bearer`.
 *  - Refresh token: long-lived, carries `jti` + `fam` (rotation family), tracked in the DB.
 * Access and refresh tokens use different secrets, so one can never be used as the other.
 */
export class TokenService {
  constructor(private readonly config: TokenServiceConfig) {}

  get accessTtlSeconds(): number {
    return this.config.accessTtlSeconds;
  }

  get refreshTtlSeconds(): number {
    return this.config.refreshTtlSeconds;
  }

  signAccessToken(user: AuthUser): string {
    return sign({ email: user.email, typ: 'access' }, this.config.accessSecret, {
      algorithm: 'HS256',
      subject: user.id,
      expiresIn: this.config.accessTtlSeconds,
      issuer: this.config.issuer,
      audience: this.config.audience,
    });
  }

  verifyAccessToken(token: string): AuthUser {
    const payload = this.verify(token, this.config.accessSecret, 'access');
    if (typeof payload.email !== 'string') throw Errors.unauthorized('Invalid access token', 'INVALID_TOKEN');
    return { id: payload.sub as string, email: payload.email };
  }

  signRefreshToken(claims: RefreshTokenClaims): string {
    return sign({ typ: 'refresh', fam: claims.familyId }, this.config.refreshSecret, {
      algorithm: 'HS256',
      subject: claims.userId,
      jwtid: claims.jti,
      expiresIn: this.config.refreshTtlSeconds,
      issuer: this.config.issuer,
      audience: this.config.audience,
    });
  }

  verifyRefreshToken(token: string, options: { ignoreExpiration?: boolean } = {}): RefreshTokenClaims {
    const payload = this.verify(token, this.config.refreshSecret, 'refresh', options.ignoreExpiration);
    if (typeof payload.jti !== 'string' || typeof payload.fam !== 'string') {
      throw Errors.unauthorized('Invalid refresh token', 'INVALID_REFRESH_TOKEN');
    }
    return { userId: payload.sub as string, jti: payload.jti, familyId: payload.fam };
  }

  private verify(token: string, secret: string, type: 'access' | 'refresh', ignoreExpiration = false): JwtPayload {
    const invalidCode = type === 'access' ? 'INVALID_TOKEN' : 'INVALID_REFRESH_TOKEN';
    try {
      const payload = verify(token, secret, {
        algorithms: ['HS256'],
        issuer: this.config.issuer,
        audience: this.config.audience,
        ignoreExpiration,
      });
      if (typeof payload === 'string' || payload.typ !== type || typeof payload.sub !== 'string') {
        throw Errors.unauthorized(`Invalid ${type} token`, invalidCode);
      }
      return payload;
    } catch (err) {
      if (err instanceof TokenExpiredError) {
        throw Errors.unauthorized(`${type === 'access' ? 'Access' : 'Refresh'} token expired`, 'TOKEN_EXPIRED');
      }
      if (err instanceof JsonWebTokenError) throw Errors.unauthorized(`Invalid ${type} token`, invalidCode);
      throw err;
    }
  }
}
