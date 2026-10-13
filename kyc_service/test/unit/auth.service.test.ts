import '../helpers/test-env';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { sign } from 'jsonwebtoken';
import { AppError } from '../../src/utils/errors';
import { STRONG_PASSWORD } from '../helpers/fixtures';
import { createTestContext } from '../helpers/test-app';

const ctx = { userAgent: 'test', ip: '127.0.0.1' };
const hasCode = (code: string) => (e: unknown) => e instanceof AppError && e.code === code;

describe('AuthService', () => {
  it('registers a user without storing the raw password', async () => {
    const { auth, users } = createTestContext();
    const { user, tokens } = await auth.register({ email: 'alice@example.com', password: STRONG_PASSWORD }, ctx);
    assert.equal(user.email, 'alice@example.com');
    assert.ok(tokens.accessToken && tokens.refreshToken);
    const stored = await users.findById(user.id);
    assert.notEqual(stored?.passwordHash, STRONG_PASSWORD);
    assert.ok(!('passwordHash' in user), 'public user must not expose the hash');
  });

  it('rejects duplicate emails', async () => {
    const { auth } = createTestContext();
    await auth.register({ email: 'dup@example.com', password: STRONG_PASSWORD }, ctx);
    await assert.rejects(
      auth.register({ email: 'dup@example.com', password: STRONG_PASSWORD }, ctx),
      hasCode('EMAIL_ALREADY_REGISTERED'),
    );
  });

  it('uses the same error for unknown email and wrong password (no user enumeration)', async () => {
    const { auth } = createTestContext();
    await auth.register({ email: 'bob@example.com', password: STRONG_PASSWORD }, ctx);
    await assert.rejects(auth.login({ email: 'bob@example.com', password: 'Wrong-Passw0rd' }, ctx), hasCode('INVALID_CREDENTIALS'));
    await assert.rejects(auth.login({ email: 'nobody@example.com', password: STRONG_PASSWORD }, ctx), hasCode('INVALID_CREDENTIALS'));
    const ok = await auth.login({ email: 'bob@example.com', password: STRONG_PASSWORD }, ctx);
    assert.equal(ok.user.email, 'bob@example.com');
  });

  it('stores refresh tokens only as hashes', async () => {
    const { auth, refreshTokens } = createTestContext();
    const { tokens } = await auth.register({ email: 'hash@example.com', password: STRONG_PASSWORD }, ctx);
    const [stored] = [...refreshTokens.tokens.values()];
    assert.notEqual(stored.tokenHash, tokens.refreshToken);
    assert.equal(stored.tokenHash.length, 64);
  });

  it('rotates refresh tokens and detects reuse of an old one', async () => {
    const { auth } = createTestContext();
    const { tokens: first } = await auth.register({ email: 'rot@example.com', password: STRONG_PASSWORD }, ctx);

    const second = await auth.refresh(first.refreshToken, ctx);
    assert.notEqual(second.refreshToken, first.refreshToken);

    // Replaying the old token = theft: rejected AND the whole session family is revoked.
    await assert.rejects(auth.refresh(first.refreshToken, ctx), hasCode('REFRESH_TOKEN_REUSED'));
    await assert.rejects(auth.refresh(second.refreshToken, ctx), hasCode('REFRESH_TOKEN_REUSED'));
  });

  it('logout revokes the session and is idempotent', async () => {
    const { auth } = createTestContext();
    const { tokens } = await auth.register({ email: 'out@example.com', password: STRONG_PASSWORD }, ctx);
    await auth.logout(tokens.refreshToken);
    await auth.logout(tokens.refreshToken);
    await auth.logout('garbage');
    await assert.rejects(auth.refresh(tokens.refreshToken, ctx), AppError);
  });

  it('separates access and refresh tokens', async () => {
    const { auth, tokens: tokenService } = createTestContext();
    const { tokens } = await auth.register({ email: 'sep@example.com', password: STRONG_PASSWORD }, ctx);
    assert.throws(() => tokenService.verifyAccessToken(tokens.refreshToken), hasCode('INVALID_TOKEN'));
    await assert.rejects(auth.refresh(tokens.accessToken, ctx), hasCode('INVALID_REFRESH_TOKEN'));
  });

  it('rejects expired and forged access tokens', () => {
    const { tokens: tokenService } = createTestContext();
    const base = { email: 'x@example.com', typ: 'access' };
    const opts = { subject: 'user-1', issuer: 'kyc-service', audience: 'kyc-app' } as const;

    const expired = sign(base, process.env.JWT_ACCESS_SECRET as string, { ...opts, expiresIn: -10 });
    assert.throws(() => tokenService.verifyAccessToken(expired), hasCode('TOKEN_EXPIRED'));

    const forged = sign(base, 'some-other-secret-0123456789-abcdefghijk', { ...opts, expiresIn: 60 });
    assert.throws(() => tokenService.verifyAccessToken(forged), hasCode('INVALID_TOKEN'));

    const none = sign(base, '', { ...opts, algorithm: 'none' });
    assert.throws(() => tokenService.verifyAccessToken(none), hasCode('INVALID_TOKEN'));
  });
});
