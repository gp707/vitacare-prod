import { Module } from '@nestjs/common';
import { AdminPushNotificationsController } from './admin-push-notifications.controller';
import { AdminPushNotificationsService } from './admin-push-notifications.service';

@Module({
  controllers: [AdminPushNotificationsController],
  providers: [AdminPushNotificationsService],
})
export class AdminPushNotificationsModule {}
