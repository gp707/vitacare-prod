import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { ScopeOfWorkService } from './scope-of-work.service';
import { UpdateScopeOfWorkDto } from './dto/update-scope-of-work.dto';

@Controller('admin/scope-of-work')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminScopeOfWorkController {
  constructor(private readonly scopeOfWorkService: ScopeOfWorkService) {}

  @Get()
  get() {
    return this.scopeOfWorkService.adminGet();
  }

  @Patch()
  update(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateScopeOfWorkDto,
    @ClientIp() ip: string | null,
  ) {
    return this.scopeOfWorkService.adminUpdate(user.sub, dto, ip);
  }
}
