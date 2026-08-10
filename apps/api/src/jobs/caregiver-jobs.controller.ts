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
import { RespondJobDto } from './dto/respond-job.dto';

@Controller('caregiver/jobs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CAREGIVER)
export class CaregiverJobsController {
  constructor(private readonly jobsService: JobsService) {}

  // Viewable at any verification status — SPEC.md 12: "browsing motivates
  // onboarding." Only responding is gated (see respond()).
  @Get()
  list(@CurrentUser() user: JwtPayload, @Query() query: ListCaregiverJobsQueryDto) {
    return this.jobsService.listActiveJobsForCaregiver(user.sub, query);
  }

  @Post(':id/respond')
  @HttpCode(HttpStatus.OK)
  respond(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: RespondJobDto,
    @ClientIp() ip: string | null,
  ) {
    return this.jobsService.respondToJob(user.sub, id, dto, ip);
  }
}
