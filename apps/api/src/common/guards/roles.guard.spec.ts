import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { RolesGuard } from './roles.guard';
import { AppException } from '../exceptions/app.exception';
import { UserRole } from '@vitacare/shared-constants';

function makeContext(user: { role: UserRole } | undefined): ExecutionContext {
  const request: any = { user };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as unknown as ExecutionContext;
}

describe('RolesGuard', () => {
  it('allows access when the route has no @Roles metadata', () => {
    const reflector = { getAllAndOverride: () => undefined } as unknown as Reflector;
    const guard = new RolesGuard(reflector);
    expect(guard.canActivate(makeContext({ role: UserRole.CAREGIVER }))).toBe(true);
  });

  it('allows access when user role is in the required roles', () => {
    const reflector = {
      getAllAndOverride: () => [UserRole.ADMIN, UserRole.SUPER_ADMIN],
    } as unknown as Reflector;
    const guard = new RolesGuard(reflector);
    expect(guard.canActivate(makeContext({ role: UserRole.ADMIN }))).toBe(true);
  });

  it('throws AUTH_007 when user role is not permitted (e.g. caregiver hitting admin route)', () => {
    const reflector = {
      getAllAndOverride: () => [UserRole.ADMIN, UserRole.SUPER_ADMIN],
    } as unknown as Reflector;
    const guard = new RolesGuard(reflector);
    expect(() => guard.canActivate(makeContext({ role: UserRole.CAREGIVER }))).toThrow(
      AppException,
    );
    try {
      guard.canActivate(makeContext({ role: UserRole.CAREGIVER }));
    } catch (e) {
      expect((e as AppException).code).toBe('AUTH_007');
    }
  });

  it('throws AUTH_007 when admin role required but super_admin-only route hit by admin', () => {
    const reflector = {
      getAllAndOverride: () => [UserRole.SUPER_ADMIN],
    } as unknown as Reflector;
    const guard = new RolesGuard(reflector);
    expect(() => guard.canActivate(makeContext({ role: UserRole.ADMIN }))).toThrow(AppException);
  });

  it('throws AUTH_007 when there is no authenticated user on the request', () => {
    const reflector = {
      getAllAndOverride: () => [UserRole.ADMIN],
    } as unknown as Reflector;
    const guard = new RolesGuard(reflector);
    expect(() => guard.canActivate(makeContext(undefined))).toThrow(AppException);
  });
});
