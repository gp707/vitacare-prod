import * as jwt from 'jsonwebtoken';
import { UserRole } from '@vitacare/shared-constants';
import { TokenService } from './token.service';

describe('TokenService', () => {
  const secret = 'test-secret';
  let configService: any;
  let service: TokenService;

  const user = (role: UserRole) => ({ id: 'user-1', role, phone: '+919876543210' });

  beforeEach(() => {
    configService = { getOrThrow: jest.fn().mockReturnValue(secret), get: jest.fn() };
    service = new TokenService(configService);
  });

  describe('signAccessToken', () => {
    it('never expires a caregiver access token (no exp claim)', () => {
      const token = service.signAccessToken(user(UserRole.CAREGIVER));
      const decoded = jwt.verify(token, secret) as jwt.JwtPayload;
      expect(decoded.exp).toBeUndefined();
    });

    it('never expires an individual (NurseNow) access token, same as caregiver', () => {
      const token = service.signAccessToken(user(UserRole.INDIVIDUAL));
      const decoded = jwt.verify(token, secret) as jwt.JwtPayload;
      expect(decoded.exp).toBeUndefined();
    });

    it('sets an expiry on admin access tokens, defaulting to 6 months', () => {
      const token = service.signAccessToken(user(UserRole.ADMIN));
      const decoded = jwt.verify(token, secret) as jwt.JwtPayload;
      expect(decoded.exp).toBeDefined();
      const ttl = decoded.exp! - decoded.iat!;
      expect(ttl).toBe(15552000);
    });

    it('sets an expiry on super_admin access tokens too', () => {
      const token = service.signAccessToken(user(UserRole.SUPER_ADMIN));
      const decoded = jwt.verify(token, secret) as jwt.JwtPayload;
      expect(decoded.exp).toBeDefined();
    });

    it('honors a configured JWT_ACCESS_TOKEN_TTL for admin tokens', () => {
      configService.get.mockImplementation((key: string) =>
        key === 'JWT_ACCESS_TOKEN_TTL' ? '60' : undefined,
      );
      const scoped = new TokenService(configService);
      const token = scoped.signAccessToken(user(UserRole.ADMIN));
      const decoded = jwt.verify(token, secret) as jwt.JwtPayload;
      expect(decoded.exp! - decoded.iat!).toBe(60);
    });
  });
});
