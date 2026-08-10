import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

/**
 * Plain-text only in V1 (CLAUDE.md: no HTML emails). Send failures are
 * logged, never thrown — a notification failing must not fail the
 * underlying registration/verification/profile-update request.
 */
@Injectable()
export class EmailService implements OnModuleInit {
  private readonly logger = new Logger(EmailService.name);
  private transporter!: nodemailer.Transporter;
  private fromAddress!: string;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    this.fromAddress = this.configService.getOrThrow<string>('SMTP_USER');
    this.transporter = nodemailer.createTransport({
      host: this.configService.getOrThrow<string>('SMTP_HOST'),
      port: this.configService.get<number>('SMTP_PORT') ?? 587,
      secure: false,
      auth: {
        user: this.fromAddress,
        pass: this.configService.getOrThrow<string>('SMTP_PASSWORD'),
      },
    });
  }

  async send(to: string, subject: string, text: string): Promise<void> {
    try {
      await this.transporter.sendMail({ from: this.fromAddress, to, subject, text });
    } catch (error) {
      this.logger.error(`Failed to send email to ${to} (subject: "${subject}")`, error);
    }
  }

  async sendToAdmin(subject: string, text: string): Promise<void> {
    const adminEmail = this.configService.getOrThrow<string>('ADMIN_NOTIFICATION_EMAIL');
    await this.send(adminEmail, subject, text);
  }
}
