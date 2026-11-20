import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminAcceptedService } from './admin-accepted.service';
import { ListAcceptedQueryDto } from './dto/list-accepted-query.dto';

/** Admin: every caregiver ever accepted onto a job or requirement, read-only. */
@Controller('admin/accepted')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminAcceptedController {
  constructor(private readonly service: AdminAcceptedService) {}

  @Get()
  list(@Query() query: ListAcceptedQueryDto) {
    return this.service.list(query);
  }
}
