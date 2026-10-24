import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { InsightsService } from './insights.service';
import {
  ActiveUsersQueryDto,
  InactiveSinceRegistrationQueryDto,
  LoginProblemsQueryDto,
  PagedInsightsQueryDto,
  TopActionsQueryDto,
} from './dto/insights-query.dto';

@Controller('admin/insights')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminInsightsController {
  constructor(private readonly insightsService: InsightsService) {}

  /** Headline counts for the Insights screen's cards. */
  @Get('summary')
  getSummary() {
    return this.insightsService.getSummary();
  }

  /** Accounts active within the last `hours` (default 24) — name, phone,
   *  display id, last seen. */
  @Get('active-users')
  listActiveUsers(@Query() query: ActiveUsersQueryDto) {
    return this.insightsService.listActiveUsers(query);
  }

  /** Accounts that registered and never came back. */
  @Get('inactive-since-registration')
  listInactiveSinceRegistration(@Query() query: InactiveSinceRegistrationQueryDto) {
    return this.insightsService.listInactiveSinceRegistration(query);
  }

  /** Patients/families and organisations with applicants but no accepted
   *  candidate, ever. */
  @Get('posters-without-accepted')
  listPostersWithoutAccepted(@Query() query: PagedInsightsQueryDto) {
    return this.insightsService.listPostersWithoutAccepted(query);
  }

  /** Caregivers who registered but have never applied to anything. */
  @Get('caregivers-never-applied')
  listCaregiversNeverApplied(@Query() query: PagedInsightsQueryDto) {
    return this.insightsService.listCaregiversNeverApplied(query);
  }

  /** People whose logins failed — wrong PIN, no account, wrong login type,
   *  deactivated, OTP problems — most recent first. Defaults to those still
   *  locked out (the ones to call). */
  @Get('login-problems')
  listLoginProblems(@Query() query: LoginProblemsQueryDto) {
    return this.insightsService.listLoginProblems(query);
  }

  /** Most-used buttons (kind=tap) or screens (kind=screen). */
  @Get('top-actions')
  getTopActions(@Query() query: TopActionsQueryDto) {
    return this.insightsService.getTopActions(query);
  }
}
