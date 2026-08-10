import { UserRole } from '@vitacare/shared-constants';

export interface JwtPayload {
  sub: string;
  role: UserRole;
  phone: string;
  iat?: number;
  exp?: number;
}

export interface RefreshTokenPayload {
  sub: string;
  jti: string;
  type: 'refresh';
  iat?: number;
  exp?: number;
}
