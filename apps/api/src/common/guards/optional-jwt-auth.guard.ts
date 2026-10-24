import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';
import { Request } from 'express';
import { JwtPayload } from '../interfaces/jwt-payload.interface';
import { UsersRepository } from '../../database/repositories/users.repository';

/** For the few endpoints that are useful both before and after login
 *  (POST /events — login/registration screens are tracked too). A valid
 *  token attaches `request.user` exactly like JwtAuthGuard does; a missing
 *  or invalid one is simply treated as anonymous — never an error, since
 *  telemetry must never be able to break the screen that sends it. A token
 *  for a deleted/deactivated account is also treated as anonymous rather
 *  than rejected, for the same reason. */
@Injectable()
export class OptionalJwtAuthGuard implements CanActivate {
  constructor(
    private readonly configService: ConfigService,
    private readonly usersRepo: UsersRepository,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: JwtPayload }>();
    const header = request.headers.authorization;
    if (!header) return true;
    const [type, token] = header.split(' ');
    if (type !== 'Bearer' || !token) return true;

    try {
      const payload = jwt.verify(token, this.configService.getOrThrow<string>('JWT_SECRET')) as JwtPayload;
      const user = await this.usersRepo.findById(payload.sub);
      if (user && user.is_active) {
        request.user = payload;
        // Sending events means the app is open — count it as activity even
        // if no other authenticated request happens to be made right now.
        void this.usersRepo.touchLastSeen(payload.sub).catch(() => undefined);
      }
    } catch {
      // Anonymous.
    }
    return true;
  }
}
