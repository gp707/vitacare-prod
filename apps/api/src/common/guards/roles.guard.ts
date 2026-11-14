import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@vitacare/shared-constants';
import { AppException } from '../exceptions/app.exception';
import { JwtPayload } from '../interfaces/jwt-payload.interface';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { isAllowedForReadOnlyAdmin } from './read-only-admin.policy';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<UserRole[] | undefined>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles || requiredRoles.length === 0) return true;

    const request = context.switchToHttp().getRequest<{
      user?: JwtPayload;
      method?: string;
      route?: { path?: string };
      path?: string;
      body?: unknown;
    }>();
    const { user } = request;

    // A read-only admin passes wherever `admin` would, then the policy narrows
    // it to reads plus a short allow-list of writes. Routes that don't list
    // `admin` (super-admin only) stay closed to it.
    if (user?.role === UserRole.READ_ONLY_ADMIN && requiredRoles.includes(UserRole.ADMIN)) {
      const routePath = request.route?.path ?? request.path ?? '';
      if (!isAllowedForReadOnlyAdmin(request.method ?? 'GET', routePath, request.body)) {
        throw new AppException('AUTH_018');
      }
      return true;
    }

    if (!user || !requiredRoles.includes(user.role)) {
      throw new AppException('AUTH_007');
    }
    return true;
  }
}
