import { Body, Controller, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Patch, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AppException } from '../common/exceptions/app.exception';
import { ErrorLogsService } from './error-logs.service';
import { ListErrorLogsQueryDto } from './dto/list-error-logs-query.dto';
import { ListAffectedUsersQueryDto } from './dto/list-affected-users-query.dto';
import { ResolveErrorLogDto } from './dto/resolve-error-log.dto';

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

  /** Everyone who has hit an unexpected error — name, phone, last error —
   *  so an admin knows who to call. */
  @Get('affected-users')
  listAffectedUsers(@Query() query: ListAffectedUsersQueryDto) {
    return this.errorLogsService.listAffectedUsers(query);
  }

  /** Resolve every open error for one person ("I called them"). */
  @Patch('users/:userId/resolve')
  @HttpCode(HttpStatus.OK)
  resolveAllForUser(
    @CurrentUser() user: JwtPayload,
    @Param('userId', new ParseUUIDPipe({ exceptionFactory: () => new AppException('GEN_005') })) userId: string,
    @Body() dto: ResolveErrorLogDto,
    @ClientIp() ip: string | null,
  ) {
    return this.errorLogsService.resolveAllForUser(userId, user.sub, dto.note, ip);
  }

  @Patch(':id/resolve')
  @HttpCode(HttpStatus.OK)
  resolve(
    @CurrentUser() user: JwtPayload,
    @Param('id', new ParseUUIDPipe({ exceptionFactory: () => new AppException('GEN_005') })) id: string,
    @Body() dto: ResolveErrorLogDto,
    @ClientIp() ip: string | null,
  ) {
    return this.errorLogsService.resolve(id, user.sub, dto.note, ip);
  }
}
