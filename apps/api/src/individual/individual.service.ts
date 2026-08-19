import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, JobApplicationStatus, JobStatus, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { DatabaseService } from '../database/database.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { CareReceiversRepository } from '../database/repositories/care-receivers.repository';
import { IndividualProfilesRepository } from '../database/repositories/individual-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { JobsService, applyCareReceiverDefaults, DUTY_TYPE_TIMES } from '../jobs/jobs.service';
import { CaregiverService } from '../caregiver/caregiver.service';
import { CreateIndividualRequirementDto } from './dto/create-individual-requirement.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';

@Injectable()
export class IndividualService {
  constructor(
    private readonly db: DatabaseService,
    private readonly jobsRepo: JobsRepository,
    private readonly jobApplicationsRepo: JobApplicationsRepository,
    private readonly careReceiversRepo: CareReceiversRepository,
    private readonly individualProfilesRepo: IndividualProfilesRepository,
    private readonly usersRepo: UsersRepository,
    private readonly jobsService: JobsService,
    private readonly auditService: AuditService,
    private readonly caregiverService: CaregiverService,
  ) {}

  /** Minimal "who am I" for session hydration on app launch — no
   *  verification pipeline to report, just identity + the job-posting
   *  block state (full block is enforced at login, not here). */
  async getMe(userId: string) {
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    return {
      user_id: user.id,
      patient_number: profile?.patient_number,
      full_name: user.full_name,
      phone: user.phone,
      is_job_posting_blocked: profile?.is_job_posting_blocked ?? false,
    };
  }

  /** Creates a job in pending_review — frequency_of_care/salary_amount are
   *  null until an admin approves it (see JobsService.updateJob). Enforces
   *  the one-live-requirement-at-a-time rule (JOB_009, pending_review
   *  counts as live) and the job-posting-blocked admin lever (JOB_010). */
  async createRequirement(
    userId: string,
    dto: CreateIndividualRequirementDto,
    ipAddress: string | null,
  ) {
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    if (profile.is_job_posting_blocked) throw new AppException('JOB_010');

    const existingLive = await this.jobsRepo.findLiveByPostedBy(userId);
    if (existingLive) throw new AppException('JOB_009');

    const { start, end } = DUTY_TYPE_TIMES[dto.duty_type];
    const job = await this.db.withTransaction(async (client) => {
      const careReceiver = await this.careReceiversRepo.create(
        applyCareReceiverDefaults(dto.care_receiver),
        client,
      );
      return this.jobsRepo.create(
        {
          care_receiver_id: careReceiver.id,
          city: dto.city,
          area: dto.area,
          description: dto.description,
          duty_type: dto.duty_type,
          frequency_of_care: null,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          salary_amount: null,
          preferred_gender: dto.preferred_gender,
          preferred_religion: dto.preferred_religion,
          posted_by: userId,
          status: JobStatus.PENDING_REVIEW,
        },
        client,
      );
    });

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_POSTED,
      entityType: 'jobs',
      entityId: job.id,
      afterValue: { duty_type: job.duty_type, city: job.city, status: job.status },
      ipAddress,
    });

    return job;
  }

  /** Full history (durable — a closed/rejected requirement stays visible,
   *  not just the current live one), each with its care_receiver joined in
   *  so the app can show the full requirement detail without a second
   *  per-job request. */
  async listMyRequirements(userId: string) {
    const jobs = await this.jobsRepo.listByPostedBy(userId);
    const careReceivers = await Promise.all(jobs.map((job) => this.careReceiversRepo.findById(job.care_receiver_id)));
    return jobs.map((job, i) => ({ ...job, care_receiver: careReceivers[i] }));
  }

  /** No re-review/verification pipeline to trigger, unlike the caregiver
   *  equivalent — an individual account has none, so this is just a plain
   *  uniqueness-checked update. */
  async updatePhone(userId: string, dto: UpdatePhoneDto, ipAddress: string | null) {
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');
    if (dto.phone === user.phone) return { message: 'Phone number updated' };

    const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [
      UserRole.INDIVIDUAL,
      UserRole.ORGANISATION,
    ]);
    if (existing) throw new AppException('AUTH_001');

    await this.usersRepo.updatePhone(userId, dto.phone);
    await this.auditService.log({
      userId,
      action: AuditAction.PHONE_CHANGED,
      entityType: 'individual_profiles',
      entityId: profile.id,
      beforeValue: { phone: user.phone },
      afterValue: { phone: dto.phone },
      ipAddress,
    });
    return { message: 'Phone number updated' };
  }

  async updateCode(userId: string, dto: UpdateCodeDto, ipAddress: string | null) {
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');

    const codeHash = await bcrypt.hash(dto.code, Config.BCRYPT_SALT_ROUNDS);
    await this.usersRepo.updateCodeHash(userId, codeHash);
    await this.auditService.log({
      userId,
      action: AuditAction.CODE_CHANGED,
      entityType: 'individual_profiles',
      entityId: profile.id,
      ipAddress,
    });
    return { message: 'Login code updated' };
  }

  async getMyRequirementApplications(userId: string, jobId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    return this.jobApplicationsRepo.findByJobId(jobId);
  }

  /** Full profile of one applicant — ownership-checked both ways (the job
   *  is the individual's own, and the application actually belongs to that
   *  job) before delegating to CaregiverService's deliberately-trimmed
   *  applicant-view shape (see getApplicantProfile there for what's
   *  omitted and why). */
  async getApplicantProfile(userId: string, jobId: string, applicationId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    const application = await this.jobApplicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('GEN_002');
    return this.caregiverService.getApplicantProfile(application.profile_id);
  }

  /** Reuses JobsService.decideApplication's full accept/reject logic
   *  (closes the job, flips the caregiver to assigned/available) — an
   *  individual deciding on their own requirement has exactly the same
   *  effect as admin deciding on it. Ownership-checked first; admin has
   *  its own separate endpoint for deciding on any job. Unlike admin's
   *  flow, a reason is mandatory when rejecting (JOB_012) — enforced here,
   *  not in the shared DecideApplicationDto, so admin's own reject stays
   *  optional. */
  async decideMyApplication(
    userId: string,
    jobId: string,
    applicationId: string,
    dto: DecideApplicationDto,
    ipAddress: string | null,
  ) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    if (dto.status === JobApplicationStatus.REJECTED && !dto.reason?.trim()) {
      throw new AppException('JOB_012');
    }
    return this.jobsService.decideApplication(userId, jobId, applicationId, dto, ipAddress);
  }
}
