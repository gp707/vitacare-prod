import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import {
  AuditAction,
  Config,
  JobApplicationStatus,
  JobStatus,
  UserRole,
  VerificationStatus,
} from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { DatabaseService } from '../database/database.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { CareReceiversRepository } from '../database/repositories/care-receivers.repository';
import { IndividualProfilesRepository } from '../database/repositories/individual-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AdminCaregiversRepository } from '../database/repositories/admin-caregivers.repository';
import { AuditService } from '../audit/audit.service';
import { JobsService, applyCareReceiverDefaults, DUTY_TYPE_TIMES } from '../jobs/jobs.service';
import { CaregiverService } from '../caregiver/caregiver.service';
import { CreateIndividualRequirementDto } from './dto/create-individual-requirement.dto';
import { UpdateIndividualRequirementDto } from './dto/update-individual-requirement.dto';
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
    private readonly adminCaregiversRepo: AdminCaregiversRepository,
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
          posted_by_role: 'individual',
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

  /** Edits any field of the individual's own requirement in place — no
   *  status change, no posted_at bump, no re-broadcast push, and no admin
   *  re-review required, unlike admin's own PATCH /admin/jobs/:id (which
   *  auto-reactivates a pending_review/closed job on save). Deliberately
   *  does NOT reuse JobsService.updateJob, since that method's repost-on-
   *  edit behavior is exactly what must NOT happen here. Allowed
   *  regardless of the requirement's current status (pending_review,
   *  active, or closed) — the only gate is whether a caregiver has
   *  already responded. frequency_of_care/salary_amount can only be set
   *  once the requirement has been through at least one admin approval
   *  (existing.frequency_of_care non-null) — before that, admin hasn't
   *  chosen them yet, so there's nothing for the individual to edit. */
  async editRequirement(
    userId: string,
    jobId: string,
    dto: UpdateIndividualRequirementDto,
    ipAddress: string | null,
  ) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');

    const hasActiveApplication = await this.jobApplicationsRepo.hasActiveApplicationForJob(jobId);
    if (hasActiveApplication) throw new AppException('JOB_014');

    const reviewedBefore = existing.frequency_of_care != null;
    if (!reviewedBefore && (dto.frequency_of_care !== undefined || dto.salary_amount !== undefined)) {
      throw new AppException('JOB_013');
    }

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
          frequency_of_care: reviewedBefore ? (dto.frequency_of_care ?? existing.frequency_of_care) : null,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          salary_amount: reviewedBefore ? (dto.salary_amount ?? existing.salary_amount) : null,
          preferred_gender: dto.preferred_gender,
          preferred_religion: dto.preferred_religion,
          // status intentionally omitted — see doc comment above.
        },
        client,
      );
    });

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_UPDATED,
      entityType: 'jobs',
      entityId: job.id,
      beforeValue: { duty_type: existing.duty_type, city: existing.city, status: existing.status },
      afterValue: { duty_type: job.duty_type, city: job.city, status: job.status },
      ipAddress,
    });

    return job;
  }

  /** Cancels the individual's own requirement — allowed at any point in
   *  its lifecycle (pending_review, active, or already closed because a
   *  candidate was accepted/filled), regardless of whether anyone has
   *  applied. The only requirements that can't be cancelled are ones
   *  already terminated some other way — admin-rejected
   *  (rejection_reason set) or already cancelled once (JOB_015 either
   *  way). Every still applied/accepted application is bulk-rejected with
   *  a fixed system reason and, for any that was accepted, that caregiver
   *  is flipped back to available — mirroring what an admin undoing a
   *  single acceptance does, just for however many applications this job
   *  happens to have at once (in practice 0 or 1 accepted, but possibly
   *  several still-applied ones alongside it). Deliberately does NOT reuse
   *  JobsService.decideApplication — its per-application accept/reopen
   *  semantics don't fit a bulk cancel-and-close. Once cancelled, the
   *  individual's own view of past applicants/phone numbers is hidden
   *  (see getMyRequirementApplications/getApplicantProfile below); the
   *  account can immediately post (or clone) a new requirement, since a
   *  cancelled job no longer counts as "live" for JOB_009. */
  async cancelRequirement(userId: string, jobId: string, ipAddress: string | null) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');
    if (existing.cancelled_at != null || existing.rejection_reason != null) {
      throw new AppException('JOB_015');
    }

    const activeApplications = await this.jobApplicationsRepo.findActiveForJob(jobId);

    await this.db.withTransaction(async (client) => {
      for (const application of activeApplications) {
        await this.jobApplicationsRepo.decide(
          application.id,
          JobApplicationStatus.REJECTED,
          userId,
          client,
          'This requirement was cancelled.',
        );
        if (application.status === JobApplicationStatus.ACCEPTED) {
          await this.adminCaregiversRepo.updateStatus(
            application.profile_id,
            VerificationStatus.AVAILABLE,
            null,
            userId,
            client,
          );
        }
      }
      await this.jobsRepo.cancel(jobId, client);
    });

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_CLOSED,
      entityType: 'jobs',
      entityId: jobId,
      beforeValue: { status: existing.status },
      afterValue: { status: 'closed', cancelled: true, rejected_applications: activeApplications.length },
      ipAddress,
    });

    return { message: 'Requirement cancelled', status: 'closed', rejected_applications: activeApplications.length };
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

  /** Once cancelled (see cancelRequirement above), the individual can no
   *  longer see who applied or their phone numbers — an empty list rather
   *  than an error, so the UI doesn't need special-case handling beyond
   *  hiding the applicants section entirely. */
  async getMyRequirementApplications(userId: string, jobId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    if (job.cancelled_at != null) return [];
    return this.jobApplicationsRepo.findByJobId(jobId);
  }

  /** Full profile of one applicant — ownership-checked both ways (the job
   *  is the individual's own, and the application actually belongs to that
   *  job) before delegating to CaregiverService's full applicant-view shape,
   *  including Aadhaar/qualification-document URLs. Unreachable once the
   *  job is cancelled — same "you can no longer see who applied" rule as
   *  getMyRequirementApplications above, treated as not-found rather than
   *  a distinct error since the UI never surfaces a stale applicationId
   *  for a cancelled requirement in the first place. */
  async getApplicantProfile(userId: string, jobId: string, applicationId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    if (job.cancelled_at != null) throw new AppException('GEN_002');
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
