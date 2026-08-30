import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';
import { Request } from 'express';
import { AppException } from '../exceptions/app.exception';
import { JwtPayload } from '../interfaces/jwt-payload.interface';
import { UsersRepository } from '../../database/repositories/users.repository';

interface CachedUserState {
  exists: boolean;
  isActive: boolean;
  expiresAt: number;
}

// How long a "does this user still exist / are they active" result is
// trusted before re-checking the DB. This guard runs on every authenticated
// request app-wide, and a handful of tokens (an admin session, a caregiver
// mid-session) can drive dozens of requests within seconds of each other —
// without this cache, that's a fresh DB round-trip per request, which was
// measured to roughly double e2e suite runtime and exhaust the shared
// Supabase connection pool (session-mode, capped at 15). 30s bounds the
// window in which a just-deleted/deactivated user's requests can still slip
// through to something meaningfully better than the pre-fix status quo
// (unbounded — never re-checked after login) without adding a DB call to
// every single request.
const CACHE_TTL_MS = 30_000;

@Injectable()
export class JwtAuthGuard implements CanActivate {
  private readonly userStateCache = new Map<string, CachedUserState>();

  constructor(
    private readonly configService: ConfigService,
    private readonly usersRepo: UsersRepository,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: JwtPayload }>();
    const token = this.extractToken(request);
    if (!token) {
      throw new AppException('AUTH_005');
    }

    let payload: JwtPayload;
    try {
      payload = jwt.verify(token, this.configService.getOrThrow<string>('JWT_SECRET')) as JwtPayload;
    } catch {
      throw new AppException('AUTH_005');
    }

    // The JWT's signature/expiry alone doesn't guarantee the account behind
    // it still exists or is still active — caregiver/individual/organisation
    // tokens never expire, and even a 6-month admin token stays
    // cryptographically valid after the underlying `users` row is deleted
    // or deactivated. Re-checking (with a short cache, see CACHE_TTL_MS)
    // means a stale token fails cleanly here (AUTH_005/AUTH_004) instead of
    // either silently succeeding into nonsense, or — for endpoints that
    // stamp an audit "updated_by"-style column with a `REFERENCES users(id)`
    // FK — crashing with an unhandled constraint-violation 500 partway
    // through a write.
    const state = await this.getUserState(payload.sub);
    if (!state.exists) {
      throw new AppException('AUTH_005');
    }
    if (!state.isActive) {
      throw new AppException('AUTH_004');
    }

    request.user = payload;
    return true;
  }

  private async getUserState(userId: string): Promise<CachedUserState> {
    const cached = this.userStateCache.get(userId);
    if (cached && cached.expiresAt > Date.now()) {
      return cached;
    }

    const user = await this.usersRepo.findById(userId);
    const state: CachedUserState = {
      exists: user !== null,
      isActive: user?.is_active ?? false,
      expiresAt: Date.now() + CACHE_TTL_MS,
    };
    this.userStateCache.set(userId, state);
    return state;
  }

  private extractToken(request: Request): string | undefined {
    const header = request.headers.authorization;
    if (!header) return undefined;
    const [type, token] = header.split(' ');
    return type === 'Bearer' ? token : undefined;
  }
}
