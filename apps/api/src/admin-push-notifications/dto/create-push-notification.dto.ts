import { ArrayMaxSize, ArrayMinSize, IsArray, IsISO8601, IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class CreatePushNotificationDto {
  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(Validation.PUSH_NOTIFICATION_TITLE_MAX_LENGTH, { message: 'GEN_001' })
  title!: string;

  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(Validation.PUSH_NOTIFICATION_BODY_MAX_LENGTH, { message: 'GEN_001' })
  body!: string;

  // Omitted, or in the past — send immediately. In the future — queued for
  // AdminPushNotificationsService's minute-poll cron to pick up.
  @IsOptional()
  @IsISO8601({}, { message: 'GEN_001' })
  scheduled_at?: string;

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @ArrayMaxSize(Validation.PUSH_NOTIFICATION_MAX_RECIPIENTS, { message: 'GEN_001' })
  @IsUUID(undefined, { each: true, message: 'GEN_001' })
  recipient_user_ids!: string[];
}
