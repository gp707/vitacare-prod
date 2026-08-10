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
  const guard = new JwtAuthGuard(configService);

  it('throws AUTH_005 when no Authorization header present', () => {
    const ctx = makeContext({});
    expect(() => guard.canActivate(ctx)).toThrow(AppException);
    try {
      guard.canActivate(ctx);
    } catch (e) {
      expect((e as AppException).code).toBe('AUTH_005');
    }
  });

  it('throws AUTH_005 for a malformed/expired token', () => {
    const expired = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+91' }, secret, {
      expiresIn: -10,
    });
    const ctx = makeContext({ authorization: `Bearer ${expired}` });
    expect(() => guard.canActivate(ctx)).toThrow(AppException);
  });

  it('attaches decoded payload to request.user and allows access for a valid token', () => {
    const token = jwt.sign({ sub: 'u1', role: 'caregiver', phone: '+919876543210' }, secret, {
      expiresIn: 3600,
    });
    const request: any = { headers: { authorization: `Bearer ${token}` } };
    const ctx = {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;

    expect(guard.canActivate(ctx)).toBe(true);
    expect(request.user.sub).toBe('u1');
    expect(request.user.role).toBe('caregiver');
  });
});
