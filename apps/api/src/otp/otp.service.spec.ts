import * as bcrypt from 'bcrypt';
import { OtpService } from './otp.service';

describe('OtpService', () => {
  let service: OtpService;
  let otpVerificationsRepo: any;
  let tokenService: any;
  let smsProvider: any;

  beforeEach(() => {
    otpVerificationsRepo = {
      create: jest.fn(),
      findLatestActive: jest.fn(),
      incrementAttempts: jest.fn(),
      markConsumed: jest.fn(),
      countRecentSends: jest.fn().mockResolvedValue(0),
      secondsSinceLastSend: jest.fn().mockResolvedValue(null),
    };
    tokenService = { signPhoneVerificationToken: jest.fn().mockReturnValue('verified-token') };
    smsProvider = { sendOtp: jest.fn().mockResolvedValue(undefined) };
    service = new OtpService(otpVerificationsRepo, tokenService, smsProvider);
  });

  describe('send', () => {
    it('throws GEN_004 when the resend cooldown has not elapsed', async () => {
      otpVerificationsRepo.secondsSinceLastSend.mockResolvedValue(10);
      await expect(service.send('+919876543210', 'nursejobs', 'register')).rejects.toMatchObject({
        code: 'GEN_004',
      });
      expect(smsProvider.sendOtp).not.toHaveBeenCalled();
    });

    it('throws GEN_004 when the rolling send cap is reached, even past the cooldown', async () => {
      otpVerificationsRepo.secondsSinceLastSend.mockResolvedValue(60);
      otpVerificationsRepo.countRecentSends.mockResolvedValue(5);
      await expect(service.send('+919876543210', 'nursejobs', 'register')).rejects.toMatchObject({
        code: 'GEN_004',
      });
      expect(smsProvider.sendOtp).not.toHaveBeenCalled();
    });

    it('generates, hashes, stores, and sends a 6-digit OTP', async () => {
      await service.send('+919876543210', 'nursejobs', 'register');

      expect(otpVerificationsRepo.create).toHaveBeenCalledTimes(1);
      const [phone, app, purpose, otpHash, expiresAt] = otpVerificationsRepo.create.mock.calls[0];
      expect(phone).toBe('+919876543210');
      expect(app).toBe('nursejobs');
      expect(purpose).toBe('register');
      expect(expiresAt).toBeInstanceOf(Date);

      const [, sentOtp] = smsProvider.sendOtp.mock.calls[0];
      expect(sentOtp).toMatch(/^\d{6}$/);
      await expect(bcrypt.compare(sentOtp, otpHash)).resolves.toBe(true);
    });

    it('propagates an SMS provider failure rather than swallowing it', async () => {
      const { AppException } = await import('../common/exceptions/app.exception');
      smsProvider.sendOtp.mockRejectedValue(new AppException('AUTH_014'));
      await expect(service.send('+919876543210', 'nursejobs', 'register')).rejects.toMatchObject({
        code: 'AUTH_014',
      });
    });
  });

  describe('verify', () => {
    it('throws AUTH_012 when no active OTP row exists (none sent, or expired)', async () => {
      otpVerificationsRepo.findLatestActive.mockResolvedValue(null);
      await expect(service.verify('+919876543210', 'nursejobs', 'register', '123456')).rejects.toMatchObject({
        code: 'AUTH_012',
      });
    });

    it('throws AUTH_012 on a wrong code, below the attempt limit', async () => {
      const otpHash = await bcrypt.hash('111111', 4);
      otpVerificationsRepo.findLatestActive.mockResolvedValue({
        id: 'otp-1',
        otp_hash: otpHash,
        attempts: 1,
        max_attempts: 5,
      });
      otpVerificationsRepo.incrementAttempts.mockResolvedValue({ attempts: 2, max_attempts: 5 });

      await expect(service.verify('+919876543210', 'nursejobs', 'register', '999999')).rejects.toMatchObject({
        code: 'AUTH_012',
      });
      expect(otpVerificationsRepo.incrementAttempts).toHaveBeenCalledWith('otp-1');
    });

    it('throws AUTH_013 once the wrong-attempt limit is reached', async () => {
      const otpHash = await bcrypt.hash('111111', 4);
      otpVerificationsRepo.findLatestActive.mockResolvedValue({
        id: 'otp-1',
        otp_hash: otpHash,
        attempts: 4,
        max_attempts: 5,
      });
      otpVerificationsRepo.incrementAttempts.mockResolvedValue({ attempts: 5, max_attempts: 5 });

      await expect(service.verify('+919876543210', 'nursejobs', 'register', '999999')).rejects.toMatchObject({
        code: 'AUTH_013',
      });
    });

    it('on a matching code, marks the row consumed and returns a signed phone-verification token', async () => {
      const otpHash = await bcrypt.hash('123456', 4);
      otpVerificationsRepo.findLatestActive.mockResolvedValue({
        id: 'otp-1',
        otp_hash: otpHash,
        attempts: 0,
        max_attempts: 5,
      });

      const token = await service.verify('+919876543210', 'nursejobs', 'register', '123456');

      expect(token).toBe('verified-token');
      expect(otpVerificationsRepo.markConsumed).toHaveBeenCalledWith('otp-1');
      expect(tokenService.signPhoneVerificationToken).toHaveBeenCalledWith({
        phone: '+919876543210',
        app: 'nursejobs',
        purpose: 'register',
      });
    });
  });
});
