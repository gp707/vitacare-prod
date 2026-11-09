import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminRejectionsService } from './admin-rejections.service';
import { ListRejectionsQueryDto } from './dto/list-rejections-query.dto';

@Controller('admin/rejections')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminRejectionsController {
  constructor(private readonly service: AdminRejectionsService) {}

  @Get()
  list(@Query() query: ListRejectionsQueryDto) {
    return this.service.list(query);
  }
}
