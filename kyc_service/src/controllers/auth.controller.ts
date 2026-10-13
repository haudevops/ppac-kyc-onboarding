import type { RequestHandler } from 'express';
import { requireUser } from '../middlewares/auth.middleware';
import type { AuthService } from '../services/auth.service';
import { clientContext, sendNoContent, sendOk, validated } from '../utils/http';
import type { LoginInput, RefreshTokenInput, RegisterInput } from '../validators/auth.schema';

/** HTTP adapter for auth: parse request -> call service -> shape response. No business logic here. */
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  register: RequestHandler = async (req, res) => {
    const result = await this.auth.register(validated<RegisterInput>(res, 'body'), clientContext(req));
    sendOk(res, result, 201);
  };

  login: RequestHandler = async (req, res) => {
    const result = await this.auth.login(validated<LoginInput>(res, 'body'), clientContext(req));
    sendOk(res, result);
  };

  refresh: RequestHandler = async (req, res) => {
    const { refreshToken } = validated<RefreshTokenInput>(res, 'body');
    sendOk(res, { tokens: await this.auth.refresh(refreshToken, clientContext(req)) });
  };

  logout: RequestHandler = async (_req, res) => {
    const { refreshToken } = validated<RefreshTokenInput>(res, 'body');
    await this.auth.logout(refreshToken);
    sendNoContent(res);
  };

  me: RequestHandler = async (req, res) => {
    sendOk(res, { user: await this.auth.me(requireUser(req.user).id) });
  };
}
