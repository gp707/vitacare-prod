import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, JobApplicationStatus, JobStatus, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { DatabaseService } from '../database/database.service';
import { FcmService } from '../fcm/fcm.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { CareReceiversRepository } from '../database/repositories/care-receivers.repository';
import { IndividualProfilesRepository } from '../database/repositories/individual-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { AuditService } from '../audit/audit.service';
import { JobsService, applyCareReceiverDefaults, DUTY_TYPE_TIMES } from '../jobs/jobs.service';
import { CaregiverService } from '../caregiver/caregiver.service';
import { CreateIndividualRequirementDto } from './dto/create-individual-requirement.dto';
import { UpdateIndividualRequirementDto } from './dto/update-individual-requirement.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';
import { UpdateNameDto } from './dto/update-name.dto';
import { UpdateFcmTokenDto } from '../caregiver/dto/update-fcm-token.dto';

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
    private readonly caregiverProfilesRepo: CaregiverProfilesRepository,
    private readonly fcmService: FcmService,
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
   *  now set immediately (client-derived from care_duration/care_receiver,
   *  same as the individual's own edit — see UpdateIndividualRequirementDto),
   *  not left null for admin to fill in on approval. admin's own approval
   *  of a pending_review requirement now only reviews content/legitimacy;
   *  it no longer needs to supply pricing. Enforces the
   *  one-live-requirement-at-a-time rule (JOB_009, pending_review counts as
   *  live) and the job-posting-blocked admin lever (JOB_010). */
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
          frequency_of_care: dto.frequency_of_care,
          start_time: start,
          end_time: end,
          start_date: dto.start_date,
          languages: dto.languages,
          salary_amount: dto.salary_amount,
          preferred_gender: dto.preferred_gender,
          preferred_religion: dto.preferred_religion,
          care_duration: dto.care_duration,
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
   *  active, or closed) — AND regardless of whether a caregiver has
   *  already applied/been accepted. This used to 409 with JOB_014 once any
   *  application existed; that lock was removed on explicit request — the
   *  frontend now warns the patient/family (and nudges them to discuss the
   *  change with existing candidates directly) instead of the backend
   *  refusing outright. Unlike individual, Organisation's own
   *  editRequirement (OrganisationRequirementsService) still enforces its
   *  own JOB_014 lock — this relaxation is Individual-specific, not a
   *  change to the shared concept. frequency_of_care/salary_amount are
   *  always editable now — both are required on the DTO and re-derived
   *  client-side on every save, same as at creation. */
  async editRequirement(
    userId: string,
    jobId: string,
    dto: UpdateIndividualRequirementDto,
    ipAddress: string | null,
  ) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');

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
          care_duration: dto.care_duration,
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
   *  is flipped back to available via the same plain status-only flip the
   *  caregiver's own self-service "mark available" endpoint uses
   *  (CaregiverProfilesRepository.markAvailable) — deliberately NOT
   *  AdminCaregiversRepository.updateStatus, which re-stamps verified_by
   *  with whoever it's given; the patient cancelling isn't a verifier, and
   *  stamping their user id there would leave a dangling identity in a
   *  column that's supposed to mean "the admin who verified this
   *  caregiver". Deliberately does NOT reuse JobsService.decideApplication
   *  either — its per-application accept/reopen semantics don't fit a
   *  bulk cancel-and-close. Once cancelled, the
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
          await this.caregiverProfilesRepo.markAvailable(application.profile_id, client);
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

  /** Self-service — brings a requirement the individual previously
   *  cancelled back to active, without needing admin to re-review (the
   *  content was already vetted the first time it went live; cancelling
   *  only ever meant "stop taking new applications", not "this needs
   *  re-approval"). Only valid from a requirement the individual itself
   *  cancelled (cancelled_at set) — an admin-rejected requirement
   *  (rejection_reason set) can never be self-reactivated, same as it can
   *  never be self-cancelled either (JOB_015 covers that case; JOB_017
   *  covers this one). Re-broadcasts a "New Job" push and stamps a fresh
   *  posted_at (restarting the apply-by urgency window), same as a repost
   *  — mirrors OrganisationRequirementsService.reactivateRequirement.
   *  Blocked the same as a brand new posting (JOB_010) while the account
   *  is job-posting-blocked — reactivating makes it visible/appliable
   *  again, same as posting new. There is no one-live-requirement check
   *  here (JOB_009) since a cancelled requirement is this account's only
   *  requirement — nothing else could be live to conflict with it. */
  async reactivateRequirement(userId: string, jobId: string, ipAddress: string | null) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');
    if (existing.cancelled_at == null) throw new AppException('JOB_017');

    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (profile?.is_job_posting_blocked) throw new AppException('JOB_010');

    const job = await this.jobsRepo.activate(jobId);

    await this.fcmService.sendToAllCaregivers(
      'New Job Available',
      'A patient/family is looking for a caregiver — check the Jobs tab.',
    );

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_UPDATED,
      entityType: 'jobs',
      entityId: jobId,
      beforeValue: { status: existing.status, cancelled: true },
      afterValue: { status: job.status, cancelled: false },
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

  /** Unlike a caregiver's full_name (locked from self-edit past
   *  registration — only admins can change it), an individual/patient can
   *  freely update their own name — there's no verification pipeline tying
   *  it to anything else, so no re-review implications either way. */
  async updateName(userId: string, dto: UpdateNameDto, ipAddress: string | null) {
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');
    if (dto.full_name === user.full_name) return { message: 'Name updated' };

    await this.usersRepo.updateFullName(userId, dto.full_name);
    await this.auditService.log({
      userId,
      action: AuditAction.PROFILE_UPDATED,
      entityType: 'individual_profiles',
      entityId: profile.id,
      beforeValue: { full_name: user.full_name },
      afterValue: { full_name: dto.full_name },
      ipAddress,
    });
    return { message: 'Name updated' };
  }

  async updateFcmToken(userId: string, dto: UpdateFcmTokenDto) {
    await this.usersRepo.updateFcmToken(userId, dto.token);
    return { message: 'FCM token updated' };
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
