import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { FeedbackService } from './feedback.service';
import { SubmitFeedbackDto } from './dto/submit-feedback.dto';
import { ListFeedbackQueryDto } from './dto/list-feedback-query.dto';

/** The patient/family's feedback about a caregiver they worked with. */
@Controller('individual/requirements')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.INDIVIDUAL)
export class IndividualFeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Get(':jobId/applications/:applicationId/feedback')
  get(@CurrentUser() user: JwtPayload, @Param('jobId') jobId: string, @Param('applicationId') applicationId: string) {
    return this.feedbackService.getForIndividual(user.sub, jobId, applicationId);
  }

  @Post(':jobId/applications/:applicationId/feedback')
  @HttpCode(HttpStatus.OK)
  submit(
    @CurrentUser() user: JwtPayload,
    @Param('jobId') jobId: string,
    @Param('applicationId') applicationId: string,
    @Body() dto: SubmitFeedbackDto,
    @ClientIp() ip: string | null,
  ) {
    return this.feedbackService.submitForIndividual(user.sub, jobId, applicationId, dto, ip);
  }
}

/** The caregiver's feedback about the family they worked for. */
@Controller('caregiver/jobs')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CAREGIVER)
export class CaregiverFeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Get(':id/feedback')
  get(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.feedbackService.getForCaregiver(user.sub, id);
  }

  @Post(':id/feedback')
  @HttpCode(HttpStatus.OK)
  submit(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: SubmitFeedbackDto,
    @ClientIp() ip: string | null,
  ) {
    return this.feedbackService.submitForCaregiver(user.sub, id, dto, ip);
  }
}

/** Admin: every feedback left, read-only. */
@Controller('admin/feedback')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminFeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Get()
  list(@Query() query: ListFeedbackQueryDto) {
    return this.feedbackService.listForAdmin(query);
  }
}
