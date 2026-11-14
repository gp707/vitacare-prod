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

  describe('read_only_admin', () => {
    const adminRoles = { getAllAndOverride: () => [UserRole.ADMIN, UserRole.SUPER_ADMIN] } as unknown as Reflector;
    const ctx = (method: string, path: string, body?: unknown) => {
      const request: any = { user: { role: UserRole.READ_ONLY_ADMIN }, method, route: { path }, body };
      return {
        switchToHttp: () => ({ getRequest: () => request }),
        getHandler: () => ({}),
        getClass: () => ({}),
      } as unknown as ExecutionContext;
    };

    it('may read an admin route', () => {
      expect(new RolesGuard(adminRoles).canActivate(ctx('GET', '/api/v1/admin/jobs'))).toBe(true);
    });

    it('may use an allow-listed write', () => {
      expect(new RolesGuard(adminRoles).canActivate(ctx('PATCH', '/api/v1/admin/tickets/:id/resolve'))).toBe(true);
    });

    it('gets AUTH_018 for any other write', () => {
      try {
        new RolesGuard(adminRoles).canActivate(ctx('POST', '/api/v1/admin/jobs'));
        fail('should have thrown');
      } catch (e) {
        expect(e).toBeInstanceOf(AppException);
        expect((e as AppException).code).toBe('AUTH_018');
      }
    });

    it('is refused on a super-admin-only route (AUTH_007)', () => {
      const superOnly = { getAllAndOverride: () => [UserRole.SUPER_ADMIN] } as unknown as Reflector;
      expect(() => new RolesGuard(superOnly).canActivate(ctx('GET', '/api/v1/admin/users'))).toThrow(AppException);
    });

    it('cannot bulk-delete jobs: that route lists only super_admin', () => {
      const superOnly = { getAllAndOverride: () => [UserRole.SUPER_ADMIN] } as unknown as Reflector;
      try {
        new RolesGuard(superOnly).canActivate(ctx('POST', '/api/v1/admin/jobs/bulk-delete'));
        fail('should have thrown');
      } catch (e) {
        expect((e as AppException).code).toBe('AUTH_007');
      }
    });

    it('leaves a plain admin completely unrestricted', () => {
      const request: any = { user: { role: UserRole.ADMIN }, method: 'POST', route: { path: '/api/v1/admin/jobs' } };
      const context = {
        switchToHttp: () => ({ getRequest: () => request }),
        getHandler: () => ({}),
        getClass: () => ({}),
      } as unknown as ExecutionContext;
      expect(new RolesGuard(adminRoles).canActivate(context)).toBe(true);
    });
  });
});
