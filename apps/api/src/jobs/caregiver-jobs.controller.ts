import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { JobsService } from './jobs.service';
import { ListCaregiverJobsQueryDto } from './dto/list-caregiver-jobs-query.dto';
import { ApplyJobDto } from './dto/apply-job.dto';

@Controller('caregiver/jobs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CAREGIVER)
export class CaregiverJobsController {
  constructor(private readonly jobsService: JobsService) {}

  // Viewable at any verification status — browsing motivates onboarding.
  // Only applying is gated (see apply()).
  @Get()
  list(@CurrentUser() user: JwtPayload, @Query() query: ListCaregiverJobsQueryDto) {
    return this.jobsService.listActiveJobsForCaregiver(user.sub, query);
  }

  // Every job the caregiver is currently accepted onto or has completed —
  // an empty array (not 404) when there are none, since that's the normal
  // state for most caregivers. A caregiver can hold more than one at once.
  @Get('assigned')
  getAssigned(@CurrentUser() user: JwtPayload) {
    return this.jobsService.listMyAssignedJobs(user.sub);
  }

  @Post(':id/apply')
  @HttpCode(HttpStatus.OK)
  apply(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: ApplyJobDto,
    @ClientIp() ip: string | null,
  ) {
    return this.jobsService.applyToJob(user.sub, id, dto, ip);
  }

  // Caregiver self-service "I finished this job" — the only way out of
  // `assigned` once they may hold several accepted jobs at once.
  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  complete(@CurrentUser() user: JwtPayload, @Param('id') id: string, @ClientIp() ip: string | null) {
    return this.jobsService.completeJob(user.sub, id, ip);
  }
}
