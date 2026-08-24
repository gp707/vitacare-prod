import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OtpController } from './otp.controller';
import { OtpSettingsController } from './otp-settings.controller';
import { AdminOtpSettingsController } from './admin-otp-settings.controller';
import { OtpService } from './otp.service';
import { OtpSettingsService } from './otp-settings.service';
import { Msg91Service } from './msg91.service';

@Module({
  imports: [AuthModule],
  controllers: [OtpController, OtpSettingsController, AdminOtpSettingsController],
  providers: [OtpService, OtpSettingsService, Msg91Service],
})
export class OtpModule {}
