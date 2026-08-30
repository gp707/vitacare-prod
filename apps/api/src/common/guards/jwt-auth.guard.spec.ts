import * as jwt from 'jsonwebtoken';
import { ExecutionContext } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AppException } from '../exceptions/app.exception';

function makeContext(headers: Record<string, string>): ExecutionContext {
  const request: any = { headers };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('JwtAuthGuard', () => {
  const secret = 'test-secret';
  const configService = { getOrThrow: () => secret } as any;
  let usersRepo: { findById: jest.Mock };
  let guard: JwtAuthGuard;

  beforeEach(() => {
    usersRepo = { findById: jest.fn() };
    guard = new JwtAuthGuard(configService, usersRepo as any);
  });

  it('throws AUTH_005 when no Authorization header present', async () => {
    const ctx = makeContext({});
    await expect(guard.canActivate(ctx)).rejects.toMatchObject({ code: 'AUTH_005' });
    expect(usersRepo.findById).not.toHaveBeenCalled();
  });

  it('throws AUTH_005 for a malformed/expired token', async () => {
    const expired = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+91' }, secret, {
      expiresIn: -10,
    });
    const ctx = makeContext({ authorization: `Bearer ${expired}` });
    await expect(guard.canActivate(ctx)).rejects.toMatchObject({ code: 'AUTH_005' });
    expect(usersRepo.findById).not.toHaveBeenCalled();
  });

  it('throws AUTH_005 when the token is well-formed but the user no longer exists (e.g. deleted account)', async () => {
    const token = jwt.sign({ sub: 'ghost', role: 'caregiver', phone: '+919876543210' }, secret, {
      expiresIn: 3600,
    });
    usersRepo.findById.mockResolvedValue(null);
    const ctx = makeContext({ authorization: `Bearer ${token}` });
    await expect(guard.canActivate(ctx)).rejects.toMatchObject({ code: 'AUTH_005' });
    expect(usersRepo.findById).toHaveBeenCalledWith('ghost');
  });

  it('throws AUTH_004 when the user exists but is deactivated', async () => {
    const token = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
      expiresIn: 3600,
    });
    usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: false });
    const ctx = makeContext({ authorization: `Bearer ${token}` });
    await expect(guard.canActivate(ctx)).rejects.toMatchObject({ code: 'AUTH_004' });
  });

  it('attaches decoded payload to request.user and allows access for a valid token belonging to an active user', async () => {
    const token = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
      expiresIn: 3600,
    });
    usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
    const request: any = { headers: { authorization: `Bearer ${token}` } };
    const ctx = {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;

    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(request.user.sub).toBe('u1');
    expect(request.user.role).toBe('caregiver');
  });

  describe('user-state caching', () => {
    // A single admin/caregiver session can drive many requests in quick
    // succession — without caching, that's a DB round-trip per request,
    // which measurably exhausted the shared connection pool under e2e-test
    // load. This is the actual behavior the cache exists to guarantee.
    it('does not re-query the DB for a second request from the same user within the cache window', async () => {
      const token = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
        expiresIn: 3600,
      });
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
      const makeCtx = () => {
        const request: any = { headers: { authorization: `Bearer ${token}` } };
        return { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext;
      };

      await guard.canActivate(makeCtx());
      await guard.canActivate(makeCtx());
      await guard.canActivate(makeCtx());

      expect(usersRepo.findById).toHaveBeenCalledTimes(1);
    });

    it('re-queries the DB for a different user even while another user is cached', async () => {
      const tokenA = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
        expiresIn: 3600,
      });
      const tokenB = jwt.sign({ sub: 'u2', role: 'caregiver', phone: '+919876543211' }, secret, {
        expiresIn: 3600,
      });
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
      const ctxFor = (token: string) => {
        const request: any = { headers: { authorization: `Bearer ${token}` } };
        return { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext;
      };

      await guard.canActivate(ctxFor(tokenA));
      await guard.canActivate(ctxFor(tokenB));

      expect(usersRepo.findById).toHaveBeenCalledTimes(2);
      expect(usersRepo.findById).toHaveBeenCalledWith('u1');
      expect(usersRepo.findById).toHaveBeenCalledWith('u2');
    });

    it('re-queries the DB once the cache entry has expired', async () => {
      jest.useFakeTimers();
      try {
        const token = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
          expiresIn: 36000,
        });
        usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
        const makeCtx = () => {
          const request: any = { headers: { authorization: `Bearer ${token}` } };
          return { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext;
        };

        await guard.canActivate(makeCtx());
        jest.advanceTimersByTime(31_000);
        await guard.canActivate(makeCtx());

        expect(usersRepo.findById).toHaveBeenCalledTimes(2);
      } finally {
        jest.useRealTimers();
      }
    });
  });
});
