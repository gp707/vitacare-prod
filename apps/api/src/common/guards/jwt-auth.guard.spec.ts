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
  let usersRepo: { findById: jest.Mock; touchLastSeen: jest.Mock };
  let guard: JwtAuthGuard;

  beforeEach(() => {
    usersRepo = { findById: jest.fn(), touchLastSeen: jest.fn().mockResolvedValue(undefined) };
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

  describe('last-seen tracking (Insights)', () => {
    const makeCtx = (token: string) => {
      const request: any = { headers: { authorization: `Bearer ${token}` } };
      return { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext;
    };
    const tokenFor = (sub: string) => jwt.sign({ sub, role: 'caregiver', phone: '+919876543210' }, secret, { expiresIn: 3600 });

    it('stamps last_seen_at on an authenticated request', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
      await guard.canActivate(makeCtx(tokenFor('u1')));
      expect(usersRepo.touchLastSeen).toHaveBeenCalledWith('u1');
    });

    it('does not stamp again for the same user inside the throttle window', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
      await guard.canActivate(makeCtx(tokenFor('u1')));
      await guard.canActivate(makeCtx(tokenFor('u1')));
      await guard.canActivate(makeCtx(tokenFor('u1')));
      expect(usersRepo.touchLastSeen).toHaveBeenCalledTimes(1);
    });

    it('stamps each distinct user independently', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'x', is_active: true });
      await guard.canActivate(makeCtx(tokenFor('u1')));
      await guard.canActivate(makeCtx(tokenFor('u2')));
      expect(usersRepo.touchLastSeen).toHaveBeenCalledTimes(2);
    });

    it('does not stamp a request that is rejected (deleted/deactivated account)', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: false });
      await expect(guard.canActivate(makeCtx(tokenFor('u1')))).rejects.toMatchObject({ code: 'AUTH_004' });
      expect(usersRepo.touchLastSeen).not.toHaveBeenCalled();
    });

    it('never fails the request when the stamp itself fails, and retries on the next request', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', is_active: true });
      usersRepo.touchLastSeen.mockRejectedValueOnce(new Error('db down'));
      await expect(guard.canActivate(makeCtx(tokenFor('u1')))).resolves.toBe(true);
      await new Promise((resolve) => setImmediate(resolve));
      await guard.canActivate(makeCtx(tokenFor('u1')));
      expect(usersRepo.touchLastSeen).toHaveBeenCalledTimes(2);
    });
  });
});
