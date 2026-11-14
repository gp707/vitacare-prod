import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';
import { UserRole } from '@vitacare/shared-constants';
import { JwtPayload, RefreshTokenPayload } from '../common/interfaces/jwt-payload.interface';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  refreshTokenExpiresAt: Date;
}

@Injectable()
export class TokenService {
  private readonly secret: string;
  private readonly accessTtlSeconds: number;
  private readonly refreshTtlSeconds: number;
  private readonly readOnlyAdminTtlSeconds: number;

  constructor(private readonly configService: ConfigService) {
    this.secret = this.configService.getOrThrow<string>('JWT_SECRET');
    // Admin web only — caregiver-app tokens never expire (see below).
    this.accessTtlSeconds = Number(this.configService.get('JWT_ACCESS_TOKEN_TTL') ?? 15552000);
    this.refreshTtlSeconds = Number(this.configService.get('JWT_REFRESH_TOKEN_TTL') ?? 2592000);
    // A read-only admin signs in again after 4 hours (default), whatever the
    // admin TTL above is.
    this.readOnlyAdminTtlSeconds = Number(this.configService.get('READ_ONLY_ADMIN_TOKEN_TTL') ?? 14400);
  }

  signAccessToken(user: { id: string; role: UserRole; phone: string }): string {
    const payload: Omit<JwtPayload, 'iat' | 'exp'> = {
      sub: user.id,
      role: user.role,
      phone: user.phone,
    };
    // Caregiver and NurseNow individual/organisation mobile apps have no
    // login-again flow in their UI — their access tokens must never
    // expire. Admin web sessions expire after JWT_ACCESS_TOKEN_TTL
    // (default 6 months).
    if (
      user.role === UserRole.CAREGIVER ||
      user.role === UserRole.INDIVIDUAL ||
      user.role === UserRole.ORGANISATION
    ) {
      return jwt.sign(payload, this.secret);
    }
    if (user.role === UserRole.READ_ONLY_ADMIN) {
      return jwt.sign(payload, this.secret, { expiresIn: this.readOnlyAdminTtlSeconds });
    }
    return jwt.sign(payload, this.secret, { expiresIn: this.accessTtlSeconds });
  }

  /** Refresh token is itself a signed JWT carrying the DB row id (jti) it corresponds to. */
  signRefreshToken(
    userId: string,
    tokenRowId: string,
    role?: UserRole,
  ): { token: string; expiresAt: Date } {
    // A read-only admin's refresh token dies with its access token (and
    // AuthService.refresh refuses them anyway), so it can never extend the session.
    const ttl = role === UserRole.READ_ONLY_ADMIN ? this.readOnlyAdminTtlSeconds : this.refreshTtlSeconds;
    const payload: Omit<RefreshTokenPayload, 'iat' | 'exp'> = {
      sub: userId,
      jti: tokenRowId,
      type: 'refresh',
    };
    const token = jwt.sign(payload, this.secret, { expiresIn: ttl });
    const expiresAt = new Date(Date.now() + ttl * 1000);
    return { token, expiresAt };
  }

  verifyRefreshToken(token: string): RefreshTokenPayload {
    return jwt.verify(token, this.secret) as RefreshTokenPayload;
  }

  /** Issued once an OTP is successfully verified — proves phone ownership
   *  for exactly one purpose (register/login) on exactly one app, for 10
   *  minutes, so it can't be replayed against the other purpose or left
   *  usable indefinitely. The `type` discriminator keeps it from ever being
   *  confused with an access/refresh token if replayed against the wrong
   *  endpoint. */
  signPhoneVerificationToken(payload: { phone: string; app: string; purpose: string }): string {
    const body: Omit<PhoneVerificationTokenPayload, 'iat' | 'exp'> = {
      ...payload,
      type: 'phone_verification',
    };
    return jwt.sign(body, this.secret, { expiresIn: 600 });
  }

  verifyPhoneVerificationToken(token: string): PhoneVerificationTokenPayload {
    return jwt.verify(token, this.secret) as PhoneVerificationTokenPayload;
  }
}

export interface PhoneVerificationTokenPayload {
  phone: string;
  app: string;
  purpose: string;
  type: 'phone_verification';
  iat?: number;
  exp?: number;
}
