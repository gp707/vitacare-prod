import { Injectable } from '@nestjs/common';
import {
  AuditAction,
  JobApplicationStatus,
  JobStatus,
  ScheduleRepeat,
  ScheduleType,
  VerificationStatus,
} from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { DatabaseService } from '../database/database.service';
import {
  OrganisationRequirementsRepository,
} from '../database/repositories/organisation-requirements.repository';
import {
  OrganisationRequirementApplicationsRepository,
} from '../database/repositories/organisation-requirement-applications.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { AdminCaregiversRepository } from '../database/repositories/admin-caregivers.repository';
import { OrganisationProfilesRepository } from '../database/repositories/organisation-profiles.repository';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { CaregiverService } from '../caregiver/caregiver.service';
import { CreateOrganisationRequirementDto } from './dto/create-organisation-requirement.dto';
import { UpdateOrganisationRequirementDto } from './dto/update-organisation-requirement.dto';
import { ListOrganisationRequirementsQueryDto } from './dto/list-organisation-requirements-query.dto';
import { ApplyJobDto } from '../jobs/dto/apply-job.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';

// Only these two can apply — same rule as the jobs pipeline: unavailable
// caregivers must toggle back to available first.
const APPLY_ELIGIBLE_STATUSES: VerificationStatus[] = [
  VerificationStatus.AVAILABLE,
  VerificationStatus.ASSIGNED,
];

/** Core requirement/application logic, shared by the org-facing,
 *  admin-facing, and caregiver-facing controllers — the organisation-phase
 *  equivalent of JobsService, but against the dedicated
 *  organisation_requirements/organisation_requirement_applications tables
 *  (see "NurseNow" in CLAUDE.md for why these aren't just more jobs rows).
 *  Unlike an Individual's postings, an organisation may have many
 *  simultaneous requirements — no one-live-at-a-time limit. */
@Injectable()
export class OrganisationRequirementsService {
  constructor(
    private readonly db: DatabaseService,
    private readonly requirementsRepo: OrganisationRequirementsRepository,
    private readonly applicationsRepo: OrganisationRequirementApplicationsRepository,
    private readonly caregiverProfilesRepo: CaregiverProfilesRepository,
    private readonly adminCaregiversRepo: AdminCaregiversRepository,
    private readonly organisationProfilesRepo: OrganisationProfilesRepository,
    private readonly fcmService: FcmService,
    private readonly auditService: AuditService,
    private readonly caregiverService: CaregiverService,
  ) {}

  async createRequirement(orgUserId: string, dto: CreateOrganisationRequirementDto, ipAddress: string | null) {
    const profile = await this.organisationProfilesRepo.findByUserId(orgUserId);
    if (!profile) throw new AppException('GEN_002');
    if (profile.is_job_posting_blocked) throw new AppException('JOB_010');

    const requirement = await this.requirementsRepo.create({
      posted_by: orgUserId,
      type_of_nurse: dto.type_of_nurse,
      accommodation_provided: dto.accommodation_provided,
      food_provided: dto.food_provided,
      special_skills: dto.special_skills ?? null,
      status: JobStatus.PENDING_REVIEW,
    });

    await this.auditService.log({
      userId: orgUserId,
      action: AuditAction.ORG_REQUIREMENT_POSTED,
      entityType: 'organisation_requirements',
      entityId: requirement.id,
      afterValue: { type_of_nurse: requirement.type_of_nurse, status: requirement.status },
      ipAddress,
    });

    return requirement;
  }

  async listMyRequirements(orgUserId: string) {
    return this.requirementsRepo.listByPostedBy(orgUserId);
  }

  async getRequirementApplications(orgUserId: string, requirementId: string) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    return this.applicationsRepo.findByRequirementId(requirementId);
  }

  /** Full profile of one applicant — ownership-checked both ways (the
   *  requirement is this org's own, and the application actually belongs
   *  to that requirement) before delegating to CaregiverService's
   *  deliberately-trimmed applicant-view shape. Organisation's review is a
   *  free list (unlike Individual's forced one-at-a-time), so this can be
   *  called for any/every applicant, not just one at a time. */
  async getApplicantProfile(orgUserId: string, requirementId: string, applicationId: string) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    const application = await this.applicationsRepo.findById(applicationId);
    if (!application || application.requirement_id !== requirementId) throw new AppException('GEN_002');
    return this.caregiverService.getApplicantProfile(application.profile_id);
  }

  /** Ownership-checked wrapper for the org's own decision — delegates to
   *  the same [decideApplication] admin uses. */
  async decideMyApplication(
    orgUserId: string,
    requirementId: string,
    applicationId: string,
    dto: DecideApplicationDto,
    ipAddress: string | null,
  ) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    return this.decideApplication(orgUserId, requirementId, applicationId, dto, ipAddress);
  }

  /** Shared accept/reject logic — used by both the org itself and admin.
   *  Mirrors JobsService.decideApplication exactly (same state machine,
   *  same caregiver verification_status side effects). */
  async decideApplication(
    actorId: string,
    requirementId: string,
    applicationId: string,
    dto: DecideApplicationDto,
    ipAddress: string | null,
  ) {
    const application = await this.applicationsRepo.findById(applicationId);
    if (!application || application.requirement_id !== requirementId) throw new AppException('JOB_006');

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
      await this.applicationsRepo.decide(applicationId, dto.status, actorId, client, dto.reason);
      if (isAcceptFromApplied) {
        await this.requirementsRepo.close(requirementId, client);
        await this.adminCaregiversRepo.updateStatus(
          application.profile_id,
          VerificationStatus.ASSIGNED,
          null,
          actorId,
          client,
        );
      } else if (isUndoAccept) {
        await this.requirementsRepo.reopen(requirementId, client);
        await this.adminCaregiversRepo.updateStatus(
          application.profile_id,
          VerificationStatus.AVAILABLE,
          null,
          actorId,
          client,
        );
      }
    });

    await this.auditService.log({
      userId: actorId,
      targetUserId: caregiverDetail.user_id,
      action: AuditAction.ORG_REQUIREMENT_APPLICATION_DECIDED,
      entityType: 'organisation_requirement_applications',
      entityId: applicationId,
      beforeValue: { status: application.status },
      afterValue: {
        status: dto.status,
        ...(isAcceptFromApplied ? { requirement_status: 'closed', caregiver_status: 'assigned' } : {}),
        ...(isUndoAccept ? { requirement_status: 'active', caregiver_status: 'available' } : {}),
      },
      ipAddress,
    });

    return { message: 'Application updated', status: dto.status };
  }

  // ---- Caregiver-facing ----

  async listActiveForCaregiver(userId: string) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return this.requirementsRepo.listActiveForCaregiver(profile.id);
  }

  async listMyAssignedRequirements(userId: string) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return this.applicationsRepo.findAssignedByProfileId(profile.id);
  }

  async applyToRequirement(userId: string, requirementId: string, dto: ApplyJobDto, ipAddress: string | null) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    if (!APPLY_ELIGIBLE_STATUSES.includes(profile.verification_status)) {
      throw new AppException('JOB_001');
    }

    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement) throw new AppException('GEN_002');
    if (requirement.status !== JobStatus.ACTIVE) throw new AppException('JOB_002');

    const application = await this.applicationsRepo.upsert(requirementId, profile.id, dto.status);

    await this.auditService.log({
      userId,
      action: AuditAction.ORG_REQUIREMENT_APPLICATION_DECIDED,
      entityType: 'organisation_requirement_applications',
      entityId: application.id,
      afterValue: { requirement_id: requirementId, status: dto.status },
      ipAddress,
    });

    return { message: 'Application recorded', status: application.status };
  }

  async completeRequirement(userId: string, requirementId: string, ipAddress: string | null) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');

    const application = await this.applicationsRepo.findByRequirementAndProfile(requirementId, profile.id);
    if (!application || application.status !== JobApplicationStatus.ACCEPTED) {
      throw new AppException('JOB_008');
    }

    let stillAssigned = false;
    await this.db.withTransaction(async (client) => {
      await this.applicationsRepo.markCompleted(application.id, client);
      const remaining = await this.applicationsRepo.countAcceptedByProfileId(profile.id, client);
      stillAssigned = remaining > 0;
      if (!stillAssigned) {
        await this.caregiverProfilesRepo.markAvailable(profile.id, client);
      }
    });

    await this.auditService.log({
      userId,
      action: AuditAction.ORG_REQUIREMENT_APPLICATION_DECIDED,
      entityType: 'organisation_requirement_applications',
      entityId: application.id,
      beforeValue: { status: 'accepted' },
      afterValue: { status: 'completed', verification_status: stillAssigned ? 'assigned' : 'available' },
      ipAddress,
    });

    return { message: 'Requirement marked complete', verification_status: stillAssigned ? 'assigned' : 'available' };
  }

  // ---- Admin-facing ----

  async listRequirementsForAdmin(query: ListOrganisationRequirementsQueryDto) {
    const { items, total } = await this.requirementsRepo.listForAdmin(
      { status: query.status },
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

  async getRequirementDetailForAdmin(id: string) {
    const requirement = await this.requirementsRepo.findById(id);
    if (!requirement) throw new AppException('GEN_002');
    const [applications, organisation] = await Promise.all([
      this.applicationsRepo.findByRequirementId(id),
      this.organisationProfilesRepo.findByUserId(requirement.posted_by),
    ]);
    return {
      ...requirement,
      applications,
      organisation_name: organisation?.organisation_name ?? null,
      organisation_type: organisation?.organisation_type ?? null,
      city: organisation?.city ?? null,
      area: organisation?.area ?? null,
    };
  }

  /** Admin edits any field — same shape/validation as create. If the
   *  requirement was pending_review, this is the approval: it activates
   *  (push-broadcasts) and stamps posted_at, same repost pattern as
   *  JobsService.updateJob. An edit of an already-active requirement does
   *  not resend the push. */
  async updateRequirement(
    adminId: string,
    id: string,
    dto: UpdateOrganisationRequirementDto,
    ipAddress: string | null,
  ) {
    const existing = await this.requirementsRepo.findById(id);
    if (!existing) throw new AppException('GEN_002');

    const shouldActivate = existing.status === JobStatus.CLOSED || existing.status === JobStatus.PENDING_REVIEW;

    const isDateRange = dto.schedule_type === ScheduleType.DATE_RANGE;
    if (isDateRange && dto.start_date && dto.end_date && dto.end_date < dto.start_date) {
      throw new AppException('ORG_001');
    }

    const isSpecificDays = dto.schedule_type === ScheduleType.SPECIFIC_DAYS;
    const isWeekly = isSpecificDays && dto.schedule_repeat === ScheduleRepeat.WEEKLY;
    if (isWeekly && dto.specific_days?.some((day) => day < 1 || day > 7)) {
      throw new AppException('ORG_002');
    }

    const requirement = await this.requirementsRepo.update(id, {
      type_of_nurse: dto.type_of_nurse,
      frequency_of_care: dto.frequency_of_care,
      salary_amount: dto.salary_amount,
      schedule_type: dto.schedule_type,
      start_date: isDateRange ? (dto.start_date ?? null) : null,
      end_date: isDateRange ? (dto.end_date ?? null) : null,
      schedule_repeat: isSpecificDays ? (dto.schedule_repeat ?? null) : null,
      specific_days: isSpecificDays ? (dto.specific_days ?? null) : null,
      accommodation_provided: dto.accommodation_provided,
      food_provided: dto.food_provided,
      special_skills: dto.special_skills ?? null,
      activate: shouldActivate,
    });

    if (shouldActivate) {
      await this.fcmService.sendToAllCaregivers(
        'New Organisation Opening',
        `A hospital/rehab is looking for a caregiver — check the Organisation Openings tab.`,
      );
    }

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.ORG_REQUIREMENT_UPDATED,
      entityType: 'organisation_requirements',
      entityId: requirement.id,
      beforeValue: { status: existing.status },
      afterValue: { status: requirement.status },
      ipAddress,
    });

    return requirement;
  }

  async rejectRequirement(adminId: string, id: string, reason: string, ipAddress: string | null) {
    const requirement = await this.requirementsRepo.findById(id);
    if (!requirement) throw new AppException('GEN_002');
    if (requirement.status !== JobStatus.PENDING_REVIEW) throw new AppException('JOB_011');

    await this.requirementsRepo.reject(id, reason, undefined);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.ORG_REQUIREMENT_REJECTED,
      entityType: 'organisation_requirements',
      entityId: id,
      afterValue: { status: 'closed', rejection_reason: reason },
      ipAddress,
    });

    return { message: 'Requirement rejected', status: JobStatus.CLOSED };
  }
}
