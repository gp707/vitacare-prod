import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminBulkDeleteService } from './admin-bulk-delete.service';
import { BulkDeleteJobsDto } from './dto/bulk-delete-jobs.dto';

// Super-admin-only, mirroring AdminUsersController's own scoping of
// severe/irreversible actions — a permanent bulk delete is a bigger blast
// radius than anything a regular admin can already do (reject/close only
// ever change status, never destroy rows), so it gets the stricter role.
@Controller('admin/jobs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.SUPER_ADMIN)
export class AdminBulkDeleteController {
  constructor(private readonly adminBulkDeleteService: AdminBulkDeleteService) {}

  @Post('bulk-delete')
  @HttpCode(HttpStatus.OK)
  bulkDelete(@CurrentUser() user: JwtPayload, @Body() dto: BulkDeleteJobsDto, @ClientIp() ip: string | null) {
    return this.adminBulkDeleteService.bulkDelete(user.sub, dto, ip);
  }
}
