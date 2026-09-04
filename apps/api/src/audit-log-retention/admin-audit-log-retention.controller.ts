import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AuditLogRetentionService } from './audit-log-retention.service';
import { UpdateAuditLogRetentionDto } from './dto/update-audit-log-retention.dto';

/** Admin-only, no public counterpart — unlike rate-card/scope-of-work/
 *  duty-requirements, no caregiver/patient app ever needs this. */
@Controller('admin/audit-log-retention')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminAuditLogRetentionController {
  constructor(private readonly auditLogRetentionService: AuditLogRetentionService) {}

  @Get()
  get() {
    return this.auditLogRetentionService.adminGet();
  }

  @Patch()
  update(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateAuditLogRetentionDto,
    @ClientIp() ip: string | null,
  ) {
    return this.auditLogRetentionService.adminUpdate(user.sub, dto, ip);
  }
}
