import { Injectable } from '@nestjs/common';
import { AuditAction, City, JobResponse, SalaryRanges, ServiceMode, VerificationStatus, WorkType } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobResponsesRepository } from '../database/repositories/job-responses.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { CreateJobDto } from './dto/create-job.dto';
import { ListJobsQueryDto } from './dto/list-jobs-query.dto';
import { ListCaregiverJobsQueryDto } from './dto/list-caregiver-jobs-query.dto';
import { RespondJobDto } from './dto/respond-job.dto';

// Only these two can respond to a job — same rule as availability itself:
// unavailable caregivers must toggle back to available first (SPEC.md 6.6).
const RESPOND_ELIGIBLE_STATUSES: VerificationStatus[] = [
  VerificationStatus.AVAILABLE,
  VerificationStatus.ASSIGNED,
];

const WORK_TYPE_LABELS: Record<WorkType, string> = {
  [WorkType.COMPANION_CARE]: 'Companion Care',
  [WorkType.BEDSIDE_CARE]: 'Bedside Care',
  [WorkType.CRITICAL_CARE]: 'Critical Care',
};

const WORK_TYPE_SALARY: Record<WorkType, { min: number; max: number }> = {
  [WorkType.COMPANION_CARE]: SalaryRanges.COMPANION_CARE,
  [WorkType.BEDSIDE_CARE]: SalaryRanges.BEDSIDE_CARE,
  [WorkType.CRITICAL_CARE]: SalaryRanges.CRITICAL_CARE,
};

const DUTY_TIMINGS_LABELS: Record<ServiceMode, string> = {
  [ServiceMode.TWENTY_FOUR_HRS_LIVE_IN]: '24Hrs (Live-In)',
  [ServiceMode.TWELVE_HRS_PG]: '12Hrs (Nearby PG)',
};

const CITY_LABELS: Record<City, string> = {
  [City.BANGALORE]: 'Bangalore',
  [City.MUMBAI]: 'Mumbai',
  [City.HYDERABAD]: 'Hyderabad',
  [City.CHENNAI]: 'Chennai',
  [City.PUNE]: 'Pune',
  [City.DELHI]: 'Delhi',
  [City.GURGAON]: 'Gurgaon',
};

@Injectable()
export class JobsService {
  constructor(
    private readonly jobsRepo: JobsRepository,
    private readonly jobResponsesRepo: JobResponsesRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly auditService: AuditService,
    private readonly fcmService: FcmService,
  ) {}

  async createJob(adminId: string, dto: CreateJobDto, ipAddress: string | null) {
    const job = await this.jobsRepo.create({
      work_type: dto.work_type,
      city: dto.city,
      description: dto.description,
      duty_timings: dto.duty_timings,
      language: dto.language,
      gender_needed: dto.gender_needed,
      religion: dto.religion,
      posted_by: adminId,
    });

    // Title/body format is exact per SPEC.md 6.7's notification table —
    // matched precisely (including the "|"-joined body and the CTA
    // suffix), not just approximated.
    const { min, max } = WORK_TYPE_SALARY[dto.work_type];
    await this.fcmService.sendToAllCaregivers(
      `New Job: ${WORK_TYPE_LABELS[dto.work_type]} - ₹${min.toLocaleString('en-IN')}–₹${max.toLocaleString('en-IN')}`,
      `${CITY_LABELS[dto.city]} | ${DUTY_TIMINGS_LABELS[dto.duty_timings]} | IMMEDIATELY APPLY`,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_POSTED,
      entityType: 'jobs',
      entityId: job.id,
      afterValue: { work_type: job.work_type, city: job.city, status: job.status },
      ipAddress,
    });

    return job;
  }

  async listJobsForAdmin(query: ListJobsQueryDto) {
    const { items, total } = await this.jobsRepo.listForAdmin(
      { status: query.status, work_type: query.work_type, city: query.city },
      { page: query.page, limit: query.limit },
    );
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }

  async getJobDetailForAdmin(jobId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');
    const responses = await this.jobResponsesRepo.findByJobId(jobId);
    return { ...job, responses };
  }

  async closeJob(adminId: string, jobId: string, ipAddress: string | null) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');

    await this.jobsRepo.close(jobId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_CLOSED,
      entityType: 'jobs',
      entityId: jobId,
      beforeValue: { status: job.status },
      afterValue: { status: 'closed' },
      ipAddress,
    });

    return { message: 'Job closed', status: 'closed' };
  }

  async sendReminder(adminId: string, jobId: string, ipAddress: string | null) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');
    if (job.status !== 'active') throw new AppException('JOB_005');

    const { min, max } = WORK_TYPE_SALARY[job.work_type];
    await this.fcmService.sendToAllCaregivers(
      `Reminder: ${WORK_TYPE_LABELS[job.work_type]} - ₹${min.toLocaleString('en-IN')}–₹${max.toLocaleString('en-IN')}`,
      `${CITY_LABELS[job.city]} | ${DUTY_TIMINGS_LABELS[job.duty_timings]} | APPLY NOW BEFORE IT'S FILLED`,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_REMINDER_SENT,
      entityType: 'jobs',
      entityId: jobId,
      afterValue: { work_type: job.work_type, city: job.city },
      ipAddress,
    });

    return { message: 'Reminder sent' };
  }

  async listActiveJobsForCaregiver(userId: string, query: ListCaregiverJobsQueryDto) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');

    const { items, total } = await this.jobsRepo.listActiveForCaregiver(profile.id, {
      page: query.page,
      limit: query.limit,
    });
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }

  async respondToJob(userId: string, jobId: string, dto: RespondJobDto, ipAddress: string | null) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    if (!RESPOND_ELIGIBLE_STATUSES.includes(profile.verification_status)) {
      throw new AppException('JOB_001');
    }

    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');
    if (job.status !== 'active') throw new AppException('JOB_002');

    const response = await this.jobResponsesRepo.upsert(
      jobId,
      profile.id,
      dto.response,
      dto.response === JobResponse.MORE_DETAILS ? (dto.message ?? null) : null,
    );

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_RESPONSE,
      entityType: 'job_responses',
      entityId: response.id,
      afterValue: { job_id: jobId, response: dto.response },
      ipAddress,
    });

    return { message: 'Response recorded', response: response.response };
  }
}
