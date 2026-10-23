import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { ErrorLogsService } from './error-logs.service';
import { ListErrorLogsQueryDto } from './dto/list-error-logs-query.dto';

class GetErrorLogStatsQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(90, { message: 'GEN_005' })
  days: number = 7;
}

@Controller('admin/error-logs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminErrorLogsController {
  constructor(private readonly errorLogsService: ErrorLogsService) {}

  @Get()
  list(@Query() query: ListErrorLogsQueryDto) {
    return this.errorLogsService.list(query);
  }

  /** Daily request/error counts — see ErrorLogsService.getStats. */
  @Get('stats')
  getStats(@Query() query: GetErrorLogStatsQueryDto) {
    return this.errorLogsService.getStats(query.days);
  }
}
