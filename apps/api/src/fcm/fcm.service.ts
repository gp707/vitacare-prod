import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { ConfigService } from '@nestjs/config';
import { App, cert, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { UsersRepository } from '../database/repositories/users.repository';

/**
 * Push notifications to caregivers (CLAUDE.md: caregivers use FCM push, not
 * email). Send failures are logged, never thrown — a notification failing
 * must not fail the underlying status-change request. Silently no-ops for
 * users with no fcm_token yet (they haven't opened the app since this
 * feature shipped, or never granted notification permission).
 */
@Injectable()
export class FcmService implements OnModuleInit {
  private readonly logger = new Logger(FcmService.name);
  private app!: App;

  constructor(
    private readonly configService: ConfigService,
    private readonly usersRepo: UsersRepository,
  ) {}

  onModuleInit(): void {
    const privateKey = this.configService
      .getOrThrow<string>('FIREBASE_PRIVATE_KEY')
      .replace(/\\n/g, '\n');

    this.app = initializeApp({
      credential: cert({
        projectId: this.configService.getOrThrow<string>('FIREBASE_PROJECT_ID'),
        clientEmail: this.configService.getOrThrow<string>('FIREBASE_CLIENT_EMAIL'),
        privateKey,
      }),
    });
  }

  async sendToUser(userId: string, title: string, body: string): Promise<void> {
    const user = await this.usersRepo.findById(userId);
    if (!user?.fcm_token) return;

    try {
      await getMessaging(this.app).send({
        token: user.fcm_token,
        notification: { title, body },
      });
    } catch (error) {
      this.logger.error(`Failed to send push notification to user ${userId}`, error);
    }
  }

  /** New-job-posted broadcast (SPEC.md 6.6) — every caregiver who has ever
   *  opened the app gets notified, regardless of verification status
   *  (browsing jobs pre-approval is the point — CLAUDE.md's "motivates
   *  onboarding" note). Silently no-ops if nobody has a token yet. */
  async sendToAllCaregivers(title: string, body: string): Promise<void> {
    const tokens = await this.usersRepo.listCaregiverFcmTokens();
    if (tokens.length === 0) return;

    try {
      await getMessaging(this.app).sendEachForMulticast({
        tokens,
        notification: { title, body },
      });
    } catch (error) {
      this.logger.error('Failed to send job-posted push broadcast', error);
    }
  }

  /** Daily 8 AM IST nudge (CLAUDE.md's Verification Status Transitions
   *  notes) — only available/unavailable caregivers get it; pending_call,
   *  assigned, and rejected caregivers have nothing to "confirm" here. No
   *  response from the caregiver = no status change, this is purely a
   *  reminder push. */
  @Cron('0 8 * * *', { timeZone: 'Asia/Kolkata' })
  async sendDailyAvailabilityReminder(): Promise<void> {
    const tokens = await this.usersRepo.listCaregiverFcmTokensByStatus(['available', 'unavailable']);
    if (tokens.length === 0) return;

    try {
      await getMessaging(this.app).sendEachForMulticast({
        tokens,
        notification: {
          title: 'Update your availability',
          body: 'Confirm your status for today — mark yourself available to keep getting job matches.',
        },
      });
    } catch (error) {
      this.logger.error('Failed to send daily availability reminder push', error);
    }
  }
}
