import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { JobsService } from './jobs.service';
import { CreateJobDto } from './dto/create-job.dto';
import { ListJobsQueryDto } from './dto/list-jobs-query.dto';
import { DecideApplicationDto } from './dto/decide-application.dto';

@Controller('admin/jobs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminJobsController {
  constructor(private readonly jobsService: JobsService) {}

  @Post()
  create(@CurrentUser() user: JwtPayload, @Body() dto: CreateJobDto, @ClientIp() ip: string | null) {
    return this.jobsService.createJob(user.sub, dto, ip);
  }

  @Get()
  list(@Query() query: ListJobsQueryDto) {
    return this.jobsService.listJobsForAdmin(query);
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.jobsService.getJobDetailForAdmin(id);
  }

  @Patch(':id')
  @HttpCode(HttpStatus.OK)
  update(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: CreateJobDto,
    @ClientIp() ip: string | null,
  ) {
    return this.jobsService.updateJob(user.sub, id, dto, ip);
  }

  @Patch(':id/close')
  @HttpCode(HttpStatus.OK)
  close(@CurrentUser() user: JwtPayload, @Param('id') id: string, @ClientIp() ip: string | null) {
    return this.jobsService.closeJob(user.sub, id, ip);
  }

  @Post(':id/remind')
  @HttpCode(HttpStatus.OK)
  remind(@CurrentUser() user: JwtPayload, @Param('id') id: string, @ClientIp() ip: string | null) {
    return this.jobsService.sendReminder(user.sub, id, ip);
  }

  @Patch(':jobId/applications/:applicationId')
  @HttpCode(HttpStatus.OK)
  decideApplication(
    @CurrentUser() user: JwtPayload,
    @Param('jobId') jobId: string,
    @Param('applicationId') applicationId: string,
    @Body() dto: DecideApplicationDto,
    @ClientIp() ip: string | null,
  ) {
    return this.jobsService.decideApplication(user.sub, jobId, applicationId, dto, ip);
  }
}
