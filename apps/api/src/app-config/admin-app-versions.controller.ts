import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AppConfigService } from './app-config.service';
import { UpdateAppVersionDto } from './dto/update-app-version.dto';

@Controller('admin/app-versions')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminAppVersionsController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get()
  list() {
    return this.appConfigService.adminList();
  }

  @Patch(':platform')
  update(
    @CurrentUser() user: JwtPayload,
    @Param('platform') platform: string,
    @Body() dto: UpdateAppVersionDto,
    @ClientIp() ip: string | null,
  ) {
    return this.appConfigService.adminUpdate(user.sub, platform, dto, ip);
  }
}
