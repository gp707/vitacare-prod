import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppException } from '../common/exceptions/app.exception';
import { SmsProvider } from './sms-provider.interface';

/**
 * MSG91 credentials aren't configured yet (no account exists). Unlike
 * EmailService (`getOrThrow` in onModuleInit, crashes app startup if
 * missing), these are read with `get` so the app boots fine either way —
 * OTP mode simply isn't usable for anyone until real creds land, which is
 * fine since no app has its flag enabled by default. Once creds exist,
 * only this file's HTTP-call body changes.
 */
@Injectable()
export class Msg91Service implements SmsProvider {
  private readonly logger = new Logger(Msg91Service.name);

  constructor(private readonly configService: ConfigService) {}

  async sendOtp(phone: string, otp: string): Promise<void> {
    const authKey = this.configService.get<string>('MSG91_AUTH_KEY');
    const templateId = this.configService.get<string>('MSG91_TEMPLATE_ID');
    const senderId = this.configService.get<string>('MSG91_SENDER_ID');

    if (!authKey || !templateId || !senderId) {
      this.logger.error('MSG91 is not configured (MSG91_AUTH_KEY/MSG91_TEMPLATE_ID/MSG91_SENDER_ID)');
      throw new AppException('AUTH_014');
    }

    // MSG91's OTP API expects the bare 10-digit number, not the +91 prefix.
    const mobile = phone.replace(/^\+91/, '91');

    let response: Response;
    try {
      response = await fetch(
        `https://control.msg91.com/api/v5/otp?template_id=${encodeURIComponent(templateId)}&mobile=${mobile}&authkey=${encodeURIComponent(authKey)}&otp=${otp}&sender=${encodeURIComponent(senderId)}`,
        { method: 'POST' },
      );
    } catch (error) {
      this.logger.error(`MSG91 request failed for ${phone}`, error);
      throw new AppException('AUTH_014');
    }

    if (!response.ok) {
      this.logger.error(`MSG91 returned ${response.status} for ${phone}`);
      throw new AppException('AUTH_014');
    }

    const body = (await response.json().catch(() => null)) as { type?: string } | null;
    if (body?.type !== 'success') {
      this.logger.error(`MSG91 responded without success for ${phone}: ${JSON.stringify(body)}`);
      throw new AppException('AUTH_014');
    }
  }
}
