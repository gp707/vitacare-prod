import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { OtpSettingsService } from './otp-settings.service';
import { UpdateOtpSettingsDto } from './dto/update-otp-settings.dto';

@Controller('admin/otp-settings')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminOtpSettingsController {
  constructor(private readonly otpSettingsService: OtpSettingsService) {}

  @Get()
  list() {
    return this.otpSettingsService.adminList();
  }

  @Patch(':app')
  update(
    @CurrentUser() user: JwtPayload,
    @Param('app') app: string,
    @Body() dto: UpdateOtpSettingsDto,
    @ClientIp() ip: string | null,
  ) {
    return this.otpSettingsService.adminUpdate(user.sub, app, dto.enabled, ip);
  }
}
