import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { JobSettingsService } from './job-settings.service';
import { UpdateJobSettingsDto } from './dto/update-job-settings.dto';

@Controller('admin/job-settings')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminJobSettingsController {
  constructor(private readonly jobSettingsService: JobSettingsService) {}

  @Get()
  get() {
    return this.jobSettingsService.adminGet();
  }

  @Patch()
  update(@CurrentUser() user: JwtPayload, @Body() dto: UpdateJobSettingsDto, @ClientIp() ip: string | null) {
    return this.jobSettingsService.adminUpdate(user.sub, dto, ip);
  }
}
