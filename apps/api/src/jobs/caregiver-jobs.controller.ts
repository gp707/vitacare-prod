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
}
