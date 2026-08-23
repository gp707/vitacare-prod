import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminReportsService } from './admin-reports.service';
import { ReportDaysQueryDto, ReportMinJobsQueryDto, ReportActivityQueryDto } from './dto/report-query.dto';

@Controller('admin/reports')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminReportsController {
  constructor(private readonly adminReportsService: AdminReportsService) {}

  @Get('caregivers/unassigned-or-no-duty')
  unassignedOrNoDuty() {
    return this.adminReportsService.findUnassignedOrNoDutyCaregivers();
  }

  @Get('caregivers/stalled-duty')
  stalledDuty(@Query() query: ReportDaysQueryDto) {
    return this.adminReportsService.findStalledDuty(query.days);
  }

  @Get('caregivers/over-threshold-active')
  overThresholdActive(@Query() query: ReportMinJobsQueryDto) {
    return this.adminReportsService.findOverThresholdActiveCaregivers(query.min_jobs);
  }

  @Get('caregivers/activity')
  caregiverActivity(@Query() query: ReportActivityQueryDto) {
    return this.adminReportsService.findCaregiverActivity(query.days, query.order);
  }

  @Get('patients/no-applicants')
  patientsWithNoApplicants(@Query() query: ReportDaysQueryDto) {
    return this.adminReportsService.findPatientsWithNoApplicants(query.days);
  }

  @Get('patients/no-pending-candidate')
  patientsWithNoPendingCandidate() {
    return this.adminReportsService.findPatientsWithNoPendingCandidate();
  }

  @Get('patients/unconverted-applicants')
  patientsWithUnconvertedApplicants() {
    return this.adminReportsService.findPatientsWithUnconvertedApplicants();
  }

  @Get('patients/activity')
  patientActivity(@Query() query: ReportActivityQueryDto) {
    return this.adminReportsService.findPatientActivity(query.days, query.order);
  }

  @Get('organisations/no-jobs-posted')
  organisationsWithNoJobsPosted() {
    return this.adminReportsService.findOrganisationsWithNoJobsPosted();
  }

  @Get('organisations/no-applicants')
  organisationsWithNoApplicants(@Query() query: ReportDaysQueryDto) {
    return this.adminReportsService.findOrganisationsWithNoApplicants(query.days);
  }

  @Get('organisations/unconverted-applicants')
  organisationsWithUnconvertedApplicants() {
    return this.adminReportsService.findOrganisationsWithUnconvertedApplicants();
  }

  @Get('organisations/activity')
  organisationActivity(@Query() query: ReportActivityQueryDto) {
    return this.adminReportsService.findOrganisationActivity(query.days, query.order);
  }
}
