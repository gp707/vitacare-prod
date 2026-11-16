import { JOB_APPLICANT_FIELDS, jobDisplayId } from '../notifications/notification-templates';
import { NotificationsService } from '../notifications/notifications.service';
import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, FrequencyOfCare, JobApplicationStatus, JobStatus, UserRole } from '@vitacare/shared-constants';
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
import { JobsService, applyCareReceiverDefaults, preferredGenderFor, DUTY_TYPE_TIMES } from '../jobs/jobs.service';
import { CaregiverService } from '../caregiver/caregiver.service';
import { CreateIndividualRequirementDto } from './dto/create-individual-requirement.dto';
import { UpdateIndividualRequirementDto } from './dto/update-individual-requirement.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';
import { UpdateNameDto } from './dto/update-name.dto';
import { SetAgreementDto } from './dto/set-agreement.dto';
import { MarkLeaveDto } from './dto/mark-leave.dto';
import { MarkCyclePaidDto } from './dto/mark-cycle-paid.dto';
import { SalaryCyclesService } from '../jobs/salary-cycles.service';
import { SalaryCyclePaymentsRepository } from '../database/repositories/salary-cycle-payments.repository';
import { JobApplicationLeavesRepository } from '../database/repositories/job-application-leaves.repository';
import { UpdateFcmTokenDto } from '../caregiver/dto/update-fcm-token.dto';
import { DeleteAccountDto } from '../caregiver/dto/delete-account.dto';

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
    private readonly notificationsService: NotificationsService,
    private readonly leavesRepo: JobApplicationLeavesRepository,
    private readonly salaryCycles: SalaryCyclesService,
    private readonly salaryPaymentsRepo: SalaryCyclePaymentsRepository,
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
      // The account's own profile name (users.full_name) otherwise defaults
      // to the bare phone number (see AuthService.registerIndividual) —
      // the Individual account IS the patient/family in the common case,
      // so whatever real name they type as the patient's own name is the
      // one worth showing everywhere the account's name is read (Patients/
      // Family list, job-poster contact card, audit logs, etc.), not just
      // on the care_receiver record. Unlike registration's own full_name
      // field (now removed from the form), this value is guaranteed to
      // exist, since patient_name is mandatory on CareReceiverDto.
      await this.usersRepo.updateFullName(userId, dto.care_receiver.patient_name, client);
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
          // Patients are no longer asked for one; today's date fills the NOT NULL column.
          start_date: dto.start_date ?? new Date().toISOString().slice(0, 10),
          languages: dto.languages,
          salary_amount: dto.salary_amount,
          preferred_gender: preferredGenderFor(dto.care_receiver, dto.preferred_gender),
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
    const existingCareReceiver = await this.careReceiversRepo.findById(existing.care_receiver_id);

    const { start, end } = DUTY_TYPE_TIMES[dto.duty_type];

    const job = await this.db.withTransaction(async (client) => {
      await this.careReceiversRepo.update(
        existing.care_receiver_id,
        applyCareReceiverDefaults(dto.care_receiver),
        client,
      );
      // Keep the account's own profile name in sync with whatever the
      // patient edits it to here too — see the matching comment in
      // createRequirement above for why.
      await this.usersRepo.updateFullName(userId, dto.care_receiver.patient_name, client);
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
          start_date: dto.start_date ?? existing.start_date,
          languages: dto.languages,
          salary_amount: dto.salary_amount,
          preferred_gender: preferredGenderFor(dto.care_receiver, dto.preferred_gender),
          preferred_religion: dto.preferred_religion,
          care_duration: dto.care_duration,
          // status intentionally omitted — see doc comment above.
        },
        client,
      );
    });
    const updatedCareReceiver = await this.careReceiversRepo.findById(existing.care_receiver_id);

    // Every field the patient can actually touch from the Patient
    // Details/Care Preferences card, diffed field-by-field against what
    // was stored before this save — the endpoint always receives the
    // form's entire current state (see JobsPostedScreen's own doc
    // comment on "whichever tick is tapped"), so this is the only way to
    // tell which field(s) the patient actually changed. Admin's audit log
    // needs every one of these spelled out individually (including
    // salary_amount) rather than a generic "job updated" entry.
    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};

    const jobFields = [
      'city',
      'area',
      'description',
      'duty_type',
      'frequency_of_care',
      'start_date',
      'salary_amount',
      'preferred_gender',
      'preferred_religion',
      'care_duration',
    ] as const;
    for (const field of jobFields) {
      if (existing[field] !== job[field]) {
        before[field] = existing[field];
        after[field] = job[field];
      }
    }

    // A new start date or shift means any duty reminders already sent were for
    // the wrong time: let the accepted caregiver get fresh ones.
    if ('start_date' in after || 'duty_type' in after) {
      await this.jobApplicationsRepo.resetDutyRemindersForJob(jobId);
    }
    // Caregivers who applied or were accepted hear about changes that matter.
    if (JOB_APPLICANT_FIELDS.some((field) => field in after)) {
      void this.notificationsService.jobUpdated(jobId, jobDisplayId(job));
    }

    const prevLanguages = [...existing.languages].sort();
    const nextLanguages = [...job.languages].sort();
    if (prevLanguages.join(',') !== nextLanguages.join(',')) {
      before.languages = prevLanguages;
      after.languages = nextLanguages;
    }

    if (existingCareReceiver && updatedCareReceiver) {
      const careReceiverFields = [
        'age',
        'gender',
        'weight_kg',
        'feeding_type',
        'has_medical_condition',
        'medical_condition_other',
        'toilet_assistance_other',
        // Not collected by nursenow-app's own form (see CLAUDE.md), but
        // CareReceiverDto still accepts them and this endpoint always
        // writes a default (false/[]) when omitted — tracked anyway so a
        // care receiver that had these set by an older flow doesn't get
        // silently cleared with no audit trail on the patient's first edit.
        'requires_vital_monitoring',
      ] as const;
      for (const field of careReceiverFields) {
        if (existingCareReceiver[field] !== updatedCareReceiver[field]) {
          before[field] = existingCareReceiver[field];
          after[field] = updatedCareReceiver[field];
        }
      }

      const prevConditions = [...existingCareReceiver.medical_conditions].sort();
      const nextConditions = [...updatedCareReceiver.medical_conditions].sort();
      if (prevConditions.join(',') !== nextConditions.join(',')) {
        before.medical_conditions = prevConditions;
        after.medical_conditions = nextConditions;
      }

      const prevToiletAssistance = [...existingCareReceiver.toilet_assistance].sort();
      const nextToiletAssistance = [...updatedCareReceiver.toilet_assistance].sort();
      if (prevToiletAssistance.join(',') !== nextToiletAssistance.join(',')) {
        before.toilet_assistance = prevToiletAssistance;
        after.toilet_assistance = nextToiletAssistance;
      }

      const prevVitalMonitoring = [...existingCareReceiver.vital_monitoring_types].sort();
      const nextVitalMonitoring = [...updatedCareReceiver.vital_monitoring_types].sort();
      if (prevVitalMonitoring.join(',') !== nextVitalMonitoring.join(',')) {
        before.vital_monitoring_types = prevVitalMonitoring;
        after.vital_monitoring_types = nextVitalMonitoring;
      }
    }

    // Skip the audit entry entirely on a no-op save (every field
    // resubmitted unchanged) — same "don't log when nothing actually
    // changed" convention as CaregiverService.editProfile.
    if (Object.keys(before).length > 0) {
      await this.auditService.log({
        userId,
        action: AuditAction.JOB_UPDATED,
        entityType: 'jobs',
        entityId: job.id,
        beforeValue: before,
        afterValue: after,
        ipAddress,
      });
    }

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
    // Looked up now: cancelling rejects every one of these applications.
    const affectedCaregivers = await this.jobApplicationsRepo.listApplicantUsers(jobId, ['applied', 'accepted']);

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
    void this.notificationsService.jobCancelled(affectedCaregivers, jobDisplayId(existing));

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
      { preferredGender: job.preferred_gender },
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

  /** "Make it live again": a closed job (a caregiver is accepted) goes back in
   *  front of caregivers WITHOUT touching anyone already accepted or applied. Fresh
   *  posted_at and a "New Job" push, same as a repost. JOB_015 for a cancelled or
   *  admin-rejected requirement (use Make Active Again / not possible), JOB_029 once
   *  permanently cancelled, JOB_031 if it is already live, JOB_010 while blocked. */
  async makeLiveAgain(userId: string, jobId: string, ipAddress: string | null) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');
    if (existing.cancelled_at != null || existing.rejection_reason != null) throw new AppException('JOB_015');
    if (existing.permanently_cancelled_at != null) throw new AppException('JOB_029');
    if (existing.status !== JobStatus.CLOSED) throw new AppException('JOB_031');

    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (profile?.is_job_posting_blocked) throw new AppException('JOB_010');

    const job = await this.jobsRepo.activate(jobId);

    await this.fcmService.sendToAllCaregivers(
      'New Job Available',
      'A patient/family is looking for a caregiver — check the Jobs tab.',
      { preferredGender: job.preferred_gender },
    );

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_UPDATED,
      entityType: 'jobs',
      entityId: jobId,
      beforeValue: { status: existing.status },
      afterValue: { status: job.status, made_live_again: true },
      ipAddress,
    });

    return job;
  }

  /** "Permanently cancel": the job is closed for good and never goes live again,
   *  and the caregivers already accepted are NOT touched (they stay accepted, with
   *  their agreement, leave and pay). Candidates still waiting (applied) are told
   *  the job is no longer taking applications. Needs at least one accepted
   *  caregiver (JOB_030); JOB_015 / JOB_029 when already cancelled, rejected or
   *  permanently cancelled. */
  async permanentlyCancelRequirement(userId: string, jobId: string, ipAddress: string | null) {
    const existing = await this.jobsRepo.findById(jobId);
    if (!existing || existing.posted_by !== userId) throw new AppException('GEN_002');
    if (existing.cancelled_at != null || existing.rejection_reason != null) throw new AppException('JOB_015');
    if (existing.permanently_cancelled_at != null) throw new AppException('JOB_029');
    if (!(await this.jobApplicationsRepo.findAcceptedForJob(jobId))) throw new AppException('JOB_030');

    const waiting = await this.jobApplicationsRepo.listApplicantUsers(jobId, ['applied']);
    const job = await this.jobsRepo.permanentlyCancel(jobId);
    if (!job) throw new AppException('JOB_015');
    void this.notificationsService.jobNoLongerOpen(waiting, jobDisplayId(existing));

    await this.auditService.log({
      userId,
      action: AuditAction.JOB_CLOSED,
      entityType: 'jobs',
      entityId: jobId,
      beforeValue: { status: existing.status },
      afterValue: { status: 'closed', permanently_cancelled: true },
      ipAddress,
    });

    return { message: 'Requirement permanently cancelled', status: job.status, permanently_cancelled: true };
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

  /** Self-service account deletion: PIN re-check, then — in one
   *  transaction — permanently deletes the requirement(s) this account
   *  posted (jobs + care_receivers, i.e. the patient's name and medical
   *  details, plus their applications) and anonymizes the users row (see
   *  UsersRepository.anonymizeAndDeactivate for why that anonymizes in place
   *  rather than deleting). A caregiver who was accepted on the deleted
   *  requirement is released back to `available`. */
  async deleteAccount(userId: string, dto: DeleteAccountDto, ipAddress: string | null = null) {
    const profile = await this.individualProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user?.code_hash || !(await bcrypt.compare(dto.code, user.code_hash))) {
      throw new AppException('AUTH_008');
    }

    await this.db.withTransaction(async (client) => {
      const { acceptedProfileIds } = await this.jobsRepo.deleteAllByPostedBy(userId, client);
      await this.caregiverProfilesRepo.releaseIfNoAcceptedWork(acceptedProfileIds, client);
      await this.usersRepo.anonymizeAndDeactivate(userId, client);
    });

    await this.auditService.log({
      userId,
      action: AuditAction.ACCOUNT_DELETED,
      entityType: 'individual_profiles',
      entityId: profile.id,
      ipAddress,
    });

    return { message: 'Account deleted' };
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
    await this.notificationsService.registerDevice(userId, dto.token);
    return { message: 'FCM token updated' };
  }

  /** Logout: forget this device only. Idempotent; scoped to this account. */
  async removeFcmToken(userId: string, dto: UpdateFcmTokenDto) {
    await this.usersRepo.removeFcmToken(userId, dto.token);
    return { message: 'FCM token removed' };
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

  // ── Leave days and salary pauses (migration 093) ─────────────────────────
  // The patient/family marks days the caregiver is on leave, cancels a marked
  // day, or pauses salary (every day until it is resumed counts as leave). All
  // of it needs an accepted caregiver with the agreement (start date) filled in.

  private static istDay(offsetDays = 0): string {
    return new Date(Date.now() + 5.5 * 3600 * 1000 + offsetDays * 24 * 3600 * 1000).toISOString().slice(0, 10);
  }

  private static isRealDate(value: string): boolean {
    const parsed = new Date(`${value}T00:00:00Z`);
    return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
  }

  /** The job (must be the caller's), the accepted application with its agreement
   *  set, and the caregiver's account to notify. */
  private async loadAcceptedWithAgreement(userId: string, jobId: string, applicationId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    const application = await this.jobApplicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('JOB_006');
    if (application.status !== JobApplicationStatus.ACCEPTED) throw new AppException('JOB_022');
    if (!application.agreed_start_date) throw new AppException('JOB_024');
    const caregiver = await this.caregiverProfilesRepo.findFullById(application.profile_id);
    return { job, application, caregiver };
  }

  private async auditLeave(
    userId: string,
    caregiverUserId: string | undefined,
    applicationId: string,
    afterValue: Record<string, unknown>,
    ipAddress: string | null,
  ) {
    await this.auditService.log({
      userId,
      targetUserId: caregiverUserId,
      action: AuditAction.JOB_LEAVE_UPDATED,
      entityType: 'job_applications',
      entityId: applicationId,
      afterValue,
      ipAddress,
    });
  }

  /** Marks days (YYYY-MM-DD) as leave. Each must be a real date on or after the
   *  agreed start date and within the next year (JOB_025). Days already marked
   *  are ignored, so tapping twice never notifies the caregiver twice. */
  async markLeaves(userId: string, jobId: string, applicationId: string, dto: MarkLeaveDto, ipAddress: string | null) {
    const { job, application, caregiver } = await this.loadAcceptedWithAgreement(userId, jobId, applicationId);
    const dates = [...new Set(dto.dates)].sort();
    const latest = IndividualService.istDay(365);
    for (const date of dates) {
      if (!IndividualService.isRealDate(date)) throw new AppException('GEN_001');
      if (date < (application.agreed_start_date as string) || date > latest) throw new AppException('JOB_025');
    }
    const added = await this.leavesRepo.addLeaves(applicationId, dates);
    if (added.length > 0) {
      if (caregiver) {
        void this.notificationsService.leaveChanged(caregiver.user_id, {
          kind: 'marked',
          displayId: jobDisplayId(job),
          dates: added,
        });
      }
      await this.auditLeave(userId, caregiver?.user_id, applicationId, { action: 'leave_marked', dates: added }, ipAddress);
    }
    return { message: added.length > 0 ? 'Leave marked' : 'Those days were already marked', ...(await this.leavesRepo.getState(applicationId)) };
  }

  /** Cancels one day that was marked as leave: it is a working day again.
   *  JOB_028 when that day was not marked (a day inside a pause ends only by
   *  resuming salary). */
  async cancelLeave(userId: string, jobId: string, applicationId: string, date: string, ipAddress: string | null) {
    const { job, caregiver } = await this.loadAcceptedWithAgreement(userId, jobId, applicationId);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !IndividualService.isRealDate(date)) throw new AppException('GEN_001');
    if (!(await this.leavesRepo.removeLeave(applicationId, date))) throw new AppException('JOB_028');
    if (caregiver) {
      void this.notificationsService.leaveChanged(caregiver.user_id, { kind: 'cancelled', displayId: jobDisplayId(job), date });
    }
    await this.auditLeave(userId, caregiver?.user_id, applicationId, { action: 'leave_cancelled', date }, ipAddress);
    return { message: 'Leave cancelled', ...(await this.leavesRepo.getState(applicationId)) };
  }

  // ── Salary cycles: the cycle-by-cycle record and "mark as paid" ──────────

  /** Every salary cycle of this caregiver on this job, newest first: paid ones as
   *  they were frozen, plus (while still accepted) the unpaid ones worked out now. */
  async listSalaryCycles(userId: string, jobId: string, applicationId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    const application = await this.jobApplicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('JOB_006');
    return { cycles: await this.salaryCycles.listForApplication(application) };
  }

  /** Marks one ended cycle as paid: freezes its dates, rate, leave days, days
   *  worked and amount with the payment date (default today, IST), and tells the
   *  caregiver. JOB_033 = no such ended cycle, JOB_034 = already paid, JOB_035 =
   *  payment date in the future or before the cycle began. */
  async markSalaryCyclePaid(
    userId: string,
    jobId: string,
    applicationId: string,
    cycleStart: string,
    dto: MarkCyclePaidDto,
    ipAddress: string | null,
  ) {
    const { job, application, caregiver } = await this.loadAcceptedWithAgreement(userId, jobId, applicationId);
    if (!IndividualService.isRealDate(cycleStart)) throw new AppException('GEN_001');
    const today = IndividualService.istDay();
    const cycles = await this.salaryCycles.listForApplication(application);
    const cycle = cycles.find((c) => c.cycle_start === cycleStart);
    if (!cycle || cycle.status === 'current') throw new AppException('JOB_033');
    if (cycle.status === 'paid') throw new AppException('JOB_034');
    const paidOn = dto.paid_on ?? today;
    if (!IndividualService.isRealDate(paidOn) || paidOn > today || paidOn < cycle.cycle_start) {
      throw new AppException('JOB_035');
    }
    const saved = await this.salaryPaymentsRepo.insert(applicationId, { ...cycle, paid_on: paidOn }, userId);
    if (!saved) throw new AppException('JOB_034');
    if (caregiver) {
      void this.notificationsService.salaryCyclePaid(caregiver.user_id, {
        displayId: jobDisplayId(job),
        cycleStart: cycle.cycle_start,
        cycleEnd: cycle.cycle_end,
        amount: cycle.amount,
        paidOn,
      });
    }
    await this.auditService.log({
      userId,
      targetUserId: caregiver?.user_id,
      action: AuditAction.JOB_SALARY_PAID,
      entityType: 'job_applications',
      entityId: applicationId,
      afterValue: { cycle_start: cycle.cycle_start, cycle_end: cycle.cycle_end, amount: cycle.amount, paid_on: paidOn },
      ipAddress,
    });
    return { message: 'Salary marked as paid', cycles: await this.salaryCycles.listForApplication(application) };
  }

  /** The popup shown to the patient/family right after they accept a
   *  caregiver: the salary and start date they agreed on, sent to the
   *  caregiver as a push and shown on their Selected card. Only while that
   *  application is still `accepted` (JOB_022); the start date can't be in
   *  the past (JOB_023, compared on the IST calendar day). Can be set again
   *  to correct it. */
  async setAgreement(
    userId: string,
    jobId: string,
    applicationId: string,
    dto: SetAgreementDto,
    ipAddress: string | null,
  ) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    const application = await this.jobApplicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('JOB_006');
    if (application.status !== JobApplicationStatus.ACCEPTED) throw new AppException('JOB_022');

    // A real calendar date (rejects 2026-02-31). The cycle start date may be in the past
    // (salary already running), but not more than a year back.
    const parsed = new Date(`${dto.agreed_start_date}T00:00:00Z`);
    if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== dto.agreed_start_date) {
      throw new AppException('GEN_001');
    }
    if (dto.agreed_start_date < IndividualService.istDay(-365)) throw new AppException('JOB_023');

    // The patient's own choice; an older app build omits it, so follow the job.
    const salaryUnit =
      dto.agreed_salary_unit ?? (job.frequency_of_care === FrequencyOfCare.DAILY ? FrequencyOfCare.DAILY : FrequencyOfCare.MONTHLY);
    const updated = await this.jobApplicationsRepo.setAgreement(
      applicationId,
      dto.agreed_salary,
      salaryUnit,
      dto.agreed_start_date,
    );
    if (!updated) throw new AppException('JOB_022');

    const caregiver = await this.caregiverProfilesRepo.findFullById(application.profile_id);
    if (caregiver) {
      void this.notificationsService.agreementSet(caregiver.user_id, {
        displayId: jobDisplayId(job),
        agreedSalary: dto.agreed_salary,
        perUnit: salaryUnit === FrequencyOfCare.DAILY ? 'day' : 'month',
        agreedStartDate: dto.agreed_start_date,
      });
    }

    await this.auditService.log({
      userId,
      targetUserId: caregiver?.user_id,
      action: AuditAction.JOB_AGREEMENT_SET,
      entityType: 'job_applications',
      entityId: applicationId,
      afterValue: {
        agreed_salary: dto.agreed_salary,
        agreed_salary_unit: salaryUnit,
        agreed_start_date: dto.agreed_start_date,
      },
      ipAddress,
    });

    return {
      message: 'Agreed salary and start date saved',
      agreed_salary: updated.agreed_salary,
      agreed_salary_unit: updated.agreed_salary_unit,
      agreed_start_date: updated.agreed_start_date,
    };
  }
}
