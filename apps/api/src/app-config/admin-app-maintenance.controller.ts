import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AppConfigService } from './app-config.service';
import { UpdateAppMaintenanceDto } from './dto/update-app-maintenance.dto';

@Controller('admin/app-maintenance')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminAppMaintenanceController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get()
  get() {
    return this.appConfigService.adminMaintenance();
  }

  @Patch()
  update(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateAppMaintenanceDto,
    @ClientIp() ip: string | null,
  ) {
    return this.appConfigService.adminMaintenanceUpdate(user.sub, dto, ip);
  }
}
