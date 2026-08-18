import { Injectable } from '@nestjs/common';
import {
  AuditAction,
  City,
  Communication,
  DutyType,
  FeedingType,
  JobApplicationStatus,
  JobStatus,
  MedicalAssistance,
  Mobility,
  ToiletAssistance,
  VerificationStatus,
} from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { DatabaseService } from '../database/database.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import {
  CareReceiversRepository,
  CreateCareReceiverInput,
} from '../database/repositories/care-receivers.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { AdminCaregiversRepository } from '../database/repositories/admin-caregivers.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { CareReceiverDto, CreateJobDto } from './dto/create-job.dto';
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

// Only age/gender/weight are hard-required on a care receiver — every other
// field is optional on the form and, if left unselected, is defaulted here
// so the persisted (and later admin-edited / caregiver-visible) value is
// always a real, explicit selection rather than null/empty.
const CARE_RECEIVER_DEFAULTS = {
  mobility: Mobility.WALKS_INDEPENDENTLY,
  communication: Communication.VERBAL,
  feeding_type: FeedingType.ORAL_INDEPENDENT,
  medical_assistance: [MedicalAssistance.MEDICATION_REMINDERS],
  toilet_assistance: [ToiletAssistance.INDEPENDENT],
} as const;

function applyCareReceiverDefaults(dto: CareReceiverDto): CreateCareReceiverInput {
  return {
    age: dto.age,
    gender: dto.gender,
    weight_kg: dto.weight_kg,
    mobility: dto.mobility ?? CARE_RECEIVER_DEFAULTS.mobility,
    communication: dto.communication ?? CARE_RECEIVER_DEFAULTS.communication,
    feeding_type: dto.feeding_type ?? CARE_RECEIVER_DEFAULTS.feeding_type,
    medical_assistance:
      dto.medical_assistance && dto.medical_assistance.length > 0
        ? dto.medical_assistance
        : [...CARE_RECEIVER_DEFAULTS.medical_assistance],
    has_medical_condition: dto.has_medical_condition ?? false,
    medical_conditions: dto.medical_conditions ?? [],
    medical_condition_other: dto.medical_condition_other ?? null,
    toilet_assistance:
      dto.toilet_assistance && dto.toilet_assistance.length > 0
        ? dto.toilet_assistance
        : [...CARE_RECEIVER_DEFAULTS.toilet_assistance],
    toilet_assistance_other: dto.toilet_assistance_other ?? null,
    requires_vital_monitoring: dto.requires_vital_monitoring ?? false,
    vital_monitoring_types: dto.vital_monitoring_types ?? [],
  };
}

@Injectable()
export class JobsService {
  constructor(
    private readonly db: DatabaseService,
    private readonly jobsRepo: JobsRepository,
    private readonly jobApplicationsRepo: JobApplicationsRepository,
    private readonly careReceiversRepo: CareReceiversRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly adminCaregiversRepo: AdminCaregiversRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
    private readonly fcmService: FcmService,
  ) {}

  async createJob(adminId: string, dto: CreateJobDto, ipAddress: string | null) {
    const job = await this.db.withTransaction(async (client) => {
      const careReceiver = await this.careReceiversRepo.create(
        applyCareReceiverDefaults(dto.care_receiver),
        client,
      );
      const { start, end } = DUTY_TYPE_TIMES[dto.duty_type];
      return this.jobsRepo.create(
        {
          care_receiver_id: careReceiver.id,
          city: dto.city,
          area: dto.area,
          description: dto.description,
          duty_type: dto.duty_type,
          frequency_of_care: dto.frequency_of_care,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          salary_amount: dto.salary_amount,
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
      {
        status: query.status,
        city: query.city,
        posted_by: query.posted_by,
        gender: query.gender,
        duty_type: query.duty_type,
        language: query.language,
      },
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

  async listJobPosters() {
    return this.jobsRepo.listPosters();
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
      await this.careReceiversRepo.update(
        existing.care_receiver_id,
        applyCareReceiverDefaults(dto.care_receiver),
        client,
      );
      return this.jobsRepo.update(
        jobId,
        {
          city: dto.city,
          area: dto.area,
          description: dto.description,
          duty_type: dto.duty_type,
          frequency_of_care: dto.frequency_of_care,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          salary_amount: dto.salary_amount,
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

    const { items, total } = await this.jobsRepo.listActiveForCaregiver(profile.id, profile.gender, {
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

  /** Every job the caregiver is currently accepted onto or has completed —
   *  `GET /caregiver/jobs` only lists active jobs, and an accepted job
   *  closes immediately, so without this a caregiver would have no way to
   *  see their own job(s) again. A caregiver can hold more than one
   *  concurrent accepted job, so this returns all of them, not just the
   *  most recent — durable history, so completed ones stay listed too.
   *  Once accepted onto a job, the caregiver can see and contact whoever
   *  posted it (name + phone only — never the admin's password/code
   *  hashes or fcm_token); that's included inline per job. */
  async listMyAssignedJobs(userId: string) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');

    return this.jobsRepo.listAssignedForCaregiver(profile.id);
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

  /** Caregiver self-service "I finished this job" — the only way out of
   *  `assigned` now that a caregiver can hold several accepted jobs at
   *  once (the old single global "Available for Jobs" button can't say
   *  which job it means). Marks just this application `completed`;
   *  verification_status only drops back to `available` once no other
   *  accepted applications remain — if others are still active, it stays
   *  `assigned`. JOB_008 covers every case where this doesn't apply: never
   *  applied, still `applied`, already `rejected`, or already
   *  `completed`. */
  async completeJob(userId: string, jobId: string, ipAddress: string | null) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');

    const application = await this.jobApplicationsRepo.findByJobAndProfile(jobId, profile.id);
    if (!application || application.status !== JobApplicationStatus.ACCEPTED) {
      throw new AppException('JOB_008');
    }

    let stillAssigned = false;
    await this.db.withTransaction(async (client) => {
      await this.jobApplicationsRepo.markCompleted(application.id, client);
      const remaining = await this.jobApplicationsRepo.countAcceptedByProfileId(profile.id, client);
      stillAssigned = remaining > 0;
      if (!stillAssigned) {
        await this.profilesRepo.markAvailable(profile.id, client);
      }
    });

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_COMPLETED,
      entityType: 'job_applications',
      entityId: application.id,
      beforeValue: { status: 'accepted' },
      afterValue: {
        status: 'completed',
        verification_status: stillAssigned ? 'assigned' : 'available',
      },
      ipAddress,
    });

    return { message: 'Job marked complete', still_assigned: stillAssigned };
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
