import { Injectable } from '@nestjs/common';
import {
  AuditAction,
  City,
  DutyType,
  JobApplicationStatus,
  JobStatus,
  VerificationStatus,
} from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { DatabaseService } from '../database/database.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { CareReceiversRepository } from '../database/repositories/care-receivers.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { AdminCaregiversRepository } from '../database/repositories/admin-caregivers.repository';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { CreateJobDto } from './dto/create-job.dto';
import { ListJobsQueryDto } from './dto/list-jobs-query.dto';
import { ListCaregiverJobsQueryDto } from './dto/list-caregiver-jobs-query.dto';
import { ApplyJobDto } from './dto/apply-job.dto';
import { DecideApplicationDto } from './dto/decide-application.dto';

// Only these two can apply to a job — same rule as availability itself:
// unavailable caregivers must toggle back to available first.
const APPLY_ELIGIBLE_STATUSES: VerificationStatus[] = [
  VerificationStatus.AVAILABLE,
  VerificationStatus.ASSIGNED,
];

const DUTY_TYPE_LABELS: Record<DutyType, string> = {
  [DutyType.DAY_DUTY]: 'Day Duty',
  [DutyType.NIGHT_DUTY]: 'Night Duty',
  [DutyType.LIVE_IN]: 'Live-In Care',
};

// Duty Type is one of exactly 3 fixed shifts — the shift's start/end time
// is implied by which one is picked, not entered separately by the admin.
const DUTY_TYPE_TIMES: Record<DutyType, { start: string | null; end: string | null }> = {
  [DutyType.DAY_DUTY]: { start: '08:00', end: '20:00' },
  [DutyType.NIGHT_DUTY]: { start: '20:00', end: '08:00' },
  [DutyType.LIVE_IN]: { start: null, end: null },
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
    private readonly db: DatabaseService,
    private readonly jobsRepo: JobsRepository,
    private readonly jobApplicationsRepo: JobApplicationsRepository,
    private readonly careReceiversRepo: CareReceiversRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly adminCaregiversRepo: AdminCaregiversRepository,
    private readonly auditService: AuditService,
    private readonly fcmService: FcmService,
  ) {}

  async createJob(adminId: string, dto: CreateJobDto, ipAddress: string | null) {
    const job = await this.db.withTransaction(async (client) => {
      const careReceiver = await this.careReceiversRepo.create(dto.care_receiver, client);
      const { start, end } = DUTY_TYPE_TIMES[dto.duty_type];
      return this.jobsRepo.create(
        {
          care_receiver_id: careReceiver.id,
          city: dto.city,
          area: dto.area,
          description: dto.description,
          duty_type: dto.duty_type,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          preferred_gender: dto.preferred_gender,
          preferred_religion: dto.preferred_religion,
          posted_by: adminId,
        },
        client,
      );
    });

    await this.fcmService.sendToAllCaregivers(
      `New Job: ${DUTY_TYPE_LABELS[job.duty_type]} in ${CITY_LABELS[job.city]}`,
      `${job.area ? `${job.area}, ` : ''}${CITY_LABELS[job.city]} | IMMEDIATELY APPLY`,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_POSTED,
      entityType: 'jobs',
      entityId: job.id,
      afterValue: { duty_type: job.duty_type, city: job.city, status: job.status },
      ipAddress,
    });

    return job;
  }

  async listJobsForAdmin(query: ListJobsQueryDto) {
    const { items, total } = await this.jobsRepo.listForAdmin(
      { status: query.status, city: query.city },
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
    const [careReceiver, applications] = await Promise.all([
      this.careReceiversRepo.findById(job.care_receiver_id),
      this.jobApplicationsRepo.findByJobId(jobId),
    ]);
    return { ...job, care_receiver: careReceiver, applications };
  }

  /** Admin edits any field of an existing job (and its care receiver) in
   *  place — same job id, existing applications untouched. If the job was
   *  `closed`, saving the edit also reposts it: status flips back to
   *  `active` and the "New Job" push re-broadcasts to all caregivers. An
   *  edit to an already-`active` job does NOT resend the push, to avoid
   *  spamming caregivers on every minor edit. */
  async updateJob(adminId: string, jobId: string, dto: CreateJobDto, ipAddress: string | null) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing) throw new AppException('GEN_002');

    const wasClosed = existing.status === 'closed';
    const { start, end } = DUTY_TYPE_TIMES[dto.duty_type];

    const job = await this.db.withTransaction(async (client) => {
      await this.careReceiversRepo.update(existing.care_receiver_id, dto.care_receiver, client);
      return this.jobsRepo.update(
        jobId,
        {
          city: dto.city,
          area: dto.area,
          description: dto.description,
          duty_type: dto.duty_type,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          preferred_gender: dto.preferred_gender,
          preferred_religion: dto.preferred_religion,
          status: wasClosed ? JobStatus.ACTIVE : undefined,
        },
        client,
      );
    });

    if (wasClosed) {
      await this.fcmService.sendToAllCaregivers(
        `New Job: ${DUTY_TYPE_LABELS[job.duty_type]} in ${CITY_LABELS[job.city]}`,
        `${job.area ? `${job.area}, ` : ''}${CITY_LABELS[job.city]} | IMMEDIATELY APPLY`,
      );
    }

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_UPDATED,
      entityType: 'jobs',
      entityId: job.id,
      beforeValue: { duty_type: existing.duty_type, city: existing.city, status: existing.status },
      afterValue: { duty_type: job.duty_type, city: job.city, status: job.status },
      ipAddress,
    });

    return job;
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

    await this.fcmService.sendToAllCaregivers(
      `Reminder: ${DUTY_TYPE_LABELS[job.duty_type]} in ${CITY_LABELS[job.city]}`,
      `${job.area ? `${job.area}, ` : ''}${CITY_LABELS[job.city]} | APPLY NOW BEFORE IT'S FILLED`,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_REMINDER_SENT,
      entityType: 'jobs',
      entityId: jobId,
      afterValue: { duty_type: job.duty_type, city: job.city },
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

  async applyToJob(userId: string, jobId: string, dto: ApplyJobDto, ipAddress: string | null) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    if (!APPLY_ELIGIBLE_STATUSES.includes(profile.verification_status)) {
      throw new AppException('JOB_001');
    }

    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');
    if (job.status !== 'active') throw new AppException('JOB_002');

    const application = await this.jobApplicationsRepo.upsert(jobId, profile.id, dto.status);

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_RESPONSE,
      entityType: 'job_applications',
      entityId: application.id,
      afterValue: { job_id: jobId, status: dto.status },
      ipAddress,
    });

    return { message: 'Application recorded', status: application.status };
  }

  /** Admin decision on a specific applicant. `accepted` closes the job and
   *  moves the caregiver to `assigned` (this IS the offer confirmation —
   *  admin has already agreed terms with the caregiver outside the app).
   *  `rejected` on a previously-`accepted` application reopens the job and
   *  moves the caregiver back to `available`; `rejected` on a still-
   *  `applied` application just declines it, no side effects. Only
   *  `applied` -> accepted/rejected and `accepted` -> rejected are valid
   *  transitions — anything else (double-accept, re-deciding an already-
   *  rejected application) is JOB_007. */
  async decideApplication(
    adminId: string,
    jobId: string,
    applicationId: string,
    dto: DecideApplicationDto,
    ipAddress: string | null,
  ) {
    const application = await this.jobApplicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('JOB_006');

    const isAcceptFromApplied =
      dto.status === JobApplicationStatus.ACCEPTED && application.status === JobApplicationStatus.APPLIED;
    const isUndoAccept =
      dto.status === JobApplicationStatus.REJECTED && application.status === JobApplicationStatus.ACCEPTED;
    const isRejectFromApplied =
      dto.status === JobApplicationStatus.REJECTED && application.status === JobApplicationStatus.APPLIED;

    if (!isAcceptFromApplied && !isUndoAccept && !isRejectFromApplied) {
      throw new AppException('JOB_007');
    }

    const caregiverDetail = await this.adminCaregiversRepo.getDetailById(application.profile_id);
    if (!caregiverDetail) throw new AppException('PROFILE_019');

    await this.db.withTransaction(async (client) => {
      await this.jobApplicationsRepo.decide(applicationId, dto.status, adminId, client);
      if (isAcceptFromApplied) {
        await this.jobsRepo.close(jobId, client);
        await this.adminCaregiversRepo.updateStatus(
          application.profile_id,
          VerificationStatus.ASSIGNED,
          null,
          adminId,
          client,
        );
      } else if (isUndoAccept) {
        await this.jobsRepo.reopen(jobId, client);
        await this.adminCaregiversRepo.updateStatus(
          application.profile_id,
          VerificationStatus.AVAILABLE,
          null,
          adminId,
          client,
        );
      }
    });

    await this.auditService.log({
      userId: adminId,
      targetUserId: caregiverDetail.user_id,
      action: AuditAction.JOB_APPLICATION_DECIDED,
      entityType: 'job_applications',
      entityId: applicationId,
      beforeValue: { status: application.status },
      afterValue: {
        status: dto.status,
        ...(isAcceptFromApplied ? { job_status: 'closed', caregiver_status: 'assigned' } : {}),
        ...(isUndoAccept ? { job_status: 'active', caregiver_status: 'available' } : {}),
      },
      ipAddress,
    });

    return { message: 'Application updated', status: dto.status };
  }
}
