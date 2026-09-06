import { Injectable } from '@nestjs/common';
import {
  AuditAction,
  CaregiverCloseReason,
  JobApplicationStatus,
  JobStatus,
  TypeOfNurse,
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
import { UpdateMyOrganisationRequirementDto } from './dto/update-my-organisation-requirement.dto';
import { AdminEditOrganisationRequirementDto } from './dto/admin-edit-organisation-requirement.dto';
import { ListOrganisationRequirementsQueryDto } from './dto/list-organisation-requirements-query.dto';
import { ApplyJobDto } from '../jobs/dto/apply-job.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';
import { CompleteRequirementDto } from './dto/complete-requirement.dto';

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

  /** class-validator's @IsNotEmpty only rejects an empty string (''), not a
   *  whitespace-only one — the same gap DUTY_001/SCOPE_001 exist for
   *  elsewhere in this codebase. Checked here instead, on every path that
   *  accepts type_of_nurse_other (create, org self-edit, admin edit). */
  private validateTypeOfNurseOther(typeOfNurse: string, typeOfNurseOther: string | undefined): void {
    if (typeOfNurse === TypeOfNurse.OTHERS && !typeOfNurseOther?.trim()) {
      throw new AppException('GEN_001');
    }
  }

  async createRequirement(orgUserId: string, dto: CreateOrganisationRequirementDto, ipAddress: string | null) {
    this.validateTypeOfNurseOther(dto.type_of_nurse, dto.type_of_nurse_other);
    const profile = await this.organisationProfilesRepo.findByUserId(orgUserId);
    if (!profile) throw new AppException('GEN_002');
    if (profile.is_job_posting_blocked) throw new AppException('JOB_010');

    const requirement = await this.requirementsRepo.create({
      posted_by: orgUserId,
      type_of_nurse: dto.type_of_nurse,
      type_of_nurse_other: dto.type_of_nurse === TypeOfNurse.OTHERS ? (dto.type_of_nurse_other ?? null) : null,
      accommodation_provided: dto.accommodation_provided,
      food_provided: dto.food_provided,
      special_skills: dto.special_skills ?? null,
      number_of_vacancies: dto.number_of_vacancies ?? 1,
      preferred_gender: dto.preferred_gender ?? null,
      duration_type: dto.duration_type,
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

  /** Edits any org-owned field of the org's own requirement in place — no
   *  status change, no posted_at bump, no re-broadcast push, and no admin
   *  re-review required, same as IndividualService.editRequirement.
   *  Allowed regardless of the requirement's current status (pending_review,
   *  active, or closed) — the only gate is whether ANY caregiver has ever
   *  applied (JOB_014), not just one still `applied`/`accepted` — a
   *  rejected or completed application locks editing too, a deliberately
   *  stricter rule than the jobs pipeline's equivalent check. There is
   *  nothing admin-owned left to protect — admin's own role is a pure
   *  approve/reject click (see approveRequirement below), no fields at
   *  all. */
  async editRequirement(
    orgUserId: string,
    id: string,
    dto: UpdateMyOrganisationRequirementDto,
    ipAddress: string | null,
  ) {
    const existing = await this.requirementsRepo.findById(id);
    if (!existing || existing.posted_by !== orgUserId) throw new AppException('GEN_002');

    this.validateTypeOfNurseOther(dto.type_of_nurse, dto.type_of_nurse_other);

    const hasAnyApplication = await this.applicationsRepo.hasAnyApplicationForRequirement(id);
    if (hasAnyApplication) throw new AppException('JOB_014');

    const requirement = await this.requirementsRepo.updateOwnFields(id, {
      type_of_nurse: dto.type_of_nurse,
      type_of_nurse_other: dto.type_of_nurse === TypeOfNurse.OTHERS ? (dto.type_of_nurse_other ?? null) : null,
      accommodation_provided: dto.accommodation_provided,
      food_provided: dto.food_provided,
      special_skills: dto.special_skills ?? null,
      number_of_vacancies: dto.number_of_vacancies,
      preferred_gender: dto.preferred_gender ?? null,
      duration_type: dto.duration_type,
    });

    await this.auditService.log({
      userId: orgUserId,
      action: AuditAction.ORG_REQUIREMENT_UPDATED,
      entityType: 'organisation_requirements',
      entityId: requirement.id,
      beforeValue: { type_of_nurse: existing.type_of_nurse, status: existing.status },
      afterValue: { type_of_nurse: requirement.type_of_nurse, status: requirement.status },
      ipAddress,
    });

    return requirement;
  }

  /** Cancels the org's own requirement — allowed at any point in its
   *  lifecycle, regardless of whether anyone has applied. The only
   *  requirements that can't be cancelled are ones already terminated some
   *  other way — admin-rejected (rejection_reason set) or already cancelled
   *  once (JOB_015 either way). Deliberately does NOT touch any existing
   *  application — unlike Individual, cancelling here means only "stop
   *  accepting new applications going forward"; every applicant's status,
   *  contact details, and profile stay exactly as they were, and the org
   *  can still accept/reject them afterward via the normal decide flow. */
  async cancelRequirement(orgUserId: string, id: string, ipAddress: string | null) {
    const existing = await this.requirementsRepo.findById(id);
    if (!existing || existing.posted_by !== orgUserId) throw new AppException('GEN_002');
    if (existing.cancelled_at != null || existing.rejection_reason != null) {
      throw new AppException('JOB_015');
    }

    await this.requirementsRepo.cancel(id);

    await this.auditService.log({
      userId: orgUserId,
      action: AuditAction.ORG_REQUIREMENT_UPDATED,
      entityType: 'organisation_requirements',
      entityId: id,
      beforeValue: { status: existing.status },
      afterValue: { status: 'closed', cancelled: true },
      ipAddress,
    });

    return { message: 'Requirement cancelled', status: 'closed' };
  }

  /** Org self-service — brings a requirement it previously cancelled back
   *  to active, without needing admin to re-review (admin's original
   *  approval already vetted the content; cancelling only ever meant "stop
   *  taking new applications for now", not "this needs re-approval").
   *  Only valid from a requirement the org itself cancelled (cancelled_at
   *  set) — an admin-rejected requirement (rejection_reason set) can never
   *  be self-reactivated, same as it can never be self-cancelled either
   *  (JOB_015 covers that case; JOB_017 covers this one). Re-broadcasts
   *  the "New Organisation Opening" push and stamps a fresh posted_at,
   *  same as admin's approveRequirement — reuses the same activate() repo
   *  method, which also clears cancelled_at. Blocked the same as a brand
   *  new posting (JOB_010) while the account is job-posting-blocked —
   *  reactivating makes it visible/appliable again, same as posting new. */
  async reactivateRequirement(orgUserId: string, id: string, ipAddress: string | null) {
    const existing = await this.requirementsRepo.findById(id);
    if (!existing || existing.posted_by !== orgUserId) throw new AppException('GEN_002');
    if (existing.cancelled_at == null) throw new AppException('JOB_017');

    const profile = await this.organisationProfilesRepo.findByUserId(orgUserId);
    if (profile?.is_job_posting_blocked) throw new AppException('JOB_010');

    const requirement = await this.requirementsRepo.activate(id);

    await this.fcmService.sendToAllCaregivers(
      'New Organisation Opening',
      `A hospital/rehab is looking for a caregiver — check the Organisation Openings tab.`,
    );

    await this.auditService.log({
      userId: orgUserId,
      action: AuditAction.ORG_REQUIREMENT_UPDATED,
      entityType: 'organisation_requirements',
      entityId: id,
      beforeValue: { status: existing.status, cancelled: true },
      afterValue: { status: requirement.status, cancelled: false },
      ipAddress,
    });

    return requirement;
  }

  /** Applicants (and their profiles/contact details) always stay visible,
   *  regardless of whether the requirement was later cancelled — cancelling
   *  only stops new applications, it never hides who already applied. */
  async getRequirementApplications(orgUserId: string, requirementId: string) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    return this.applicationsRepo.findByRequirementId(requirementId);
  }

  /** Full profile of one applicant — ownership-checked both ways (the
   *  requirement is this org's own, and the application actually belongs
   *  to that requirement) before delegating to CaregiverService's full
   *  applicant-view shape, including Aadhaar/qualification-document URLs.
   *  Organisation's review is a free list (unlike Individual's forced
   *  one-at-a-time), so this can be called for any/every applicant, not
   *  just one at a time. */
  async getApplicantProfile(orgUserId: string, requirementId: string, applicationId: string) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    const application = await this.applicationsRepo.findById(applicationId);
    if (!application || application.requirement_id !== requirementId) throw new AppException('GEN_002');
    return this.caregiverService.getApplicantProfile(application.profile_id);
  }

  /** Ownership-checked wrapper for the org's own decision — delegates to
   *  the same [decideApplication] admin uses. Rejecting requires a reason
   *  (JOB_012) — mirrors IndividualService.decideMyApplication; admin's own
   *  reject flow (calling decideApplication directly) stays reason-optional,
   *  same asymmetry as the jobs pipeline. */
  async decideMyApplication(
    orgUserId: string,
    requirementId: string,
    applicationId: string,
    dto: DecideApplicationDto,
    ipAddress: string | null,
  ) {
    const requirement = await this.requirementsRepo.findById(requirementId);
    if (!requirement || requirement.posted_by !== orgUserId) throw new AppException('GEN_002');
    if (dto.status === JobApplicationStatus.REJECTED && !dto.reason?.trim()) {
      throw new AppException('JOB_012');
    }
    return this.decideApplication(orgUserId, requirementId, applicationId, dto, ipAddress);
  }

  /** Shared accept/reject logic — used by both the org itself and admin.
   *  `accepted` is valid from `applied` (a normal accept), `rejected`
   *  ("Accept Anyway" — reconsidering either side's earlier decline), or
   *  `completed` (re-engaging a caregiver who already closed this same
   *  requirement themselves). Any number of applicants can be `accepted`
   *  on a requirement at once — `number_of_vacancies` is purely informational
   *  (what the org told caregivers it's hiring for), never enforced as a
   *  cap on how many can actually be accepted; an earlier iteration
   *  capped accepting at that number (JOB_019), which was reversed on
   *  explicit follow-up request. `rejected` on a previously-`accepted`
   *  application undoes that one acceptance; `rejected` on a still-`applied`
   *  application just declines it. Anything else is JOB_007. Never checks
   *  or changes the requirement's own status (active/closed/cancelled) —
   *  unlike JobsService's own decideApplication, accepting a candidate here
   *  deliberately does NOT close the requirement (an org may want more than
   *  one caregiver for the same posting), so it stays active/live and
   *  visible to other caregivers throughout, and a rejected candidate can
   *  be reselected even after the requirement was separately cancelled. */
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
    const isAcceptFromRejected =
      dto.status === JobApplicationStatus.ACCEPTED && application.status === JobApplicationStatus.REJECTED;
    const isAcceptFromCompleted =
      dto.status === JobApplicationStatus.ACCEPTED && application.status === JobApplicationStatus.COMPLETED;
    const isUndoAccept =
      dto.status === JobApplicationStatus.REJECTED && application.status === JobApplicationStatus.ACCEPTED;
    const isRejectFromApplied =
      dto.status === JobApplicationStatus.REJECTED && application.status === JobApplicationStatus.APPLIED;
    const isAccepting = isAcceptFromApplied || isAcceptFromRejected || isAcceptFromCompleted;

    if (!isAccepting && !isUndoAccept && !isRejectFromApplied) {
      throw new AppException('JOB_007');
    }

    const caregiverDetail = await this.adminCaregiversRepo.getDetailById(application.profile_id);
    if (!caregiverDetail) throw new AppException('PROFILE_019');

    await this.db.withTransaction(async (client) => {
      await this.applicationsRepo.decide(applicationId, dto.status, actorId, client, dto.reason);
      if (isAccepting) {
        await this.adminCaregiversRepo.updateStatus(
          application.profile_id,
          VerificationStatus.ASSIGNED,
          null,
          actorId,
          client,
        );
      } else if (isUndoAccept) {
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
        ...(isAccepting ? { caregiver_status: 'assigned' } : {}),
        ...(isUndoAccept ? { caregiver_status: 'available' } : {}),
      },
      ipAddress,
    });

    return { message: 'Application updated', status: dto.status };
  }

  // ---- Caregiver-facing ----

  async listActiveForCaregiver(userId: string) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return this.requirementsRepo.listActiveForCaregiver(profile.id, profile.gender);
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

  /** Caregiver self-service "I'm done with this requirement" — effectively
   *  rejecting it for herself, not a statement that the org's need is
   *  over. The requirement's own status is never touched here (it was
   *  never closed by acceptance in the first place — see decideApplication
   *  above), regardless of whether other `applied` candidates remain or
   *  none at all. See JobsService.completeJob for the caregiver-status
   *  side of this reasoning (identical shape, mirrored table). */
  async completeRequirement(
    userId: string,
    requirementId: string,
    dto: CompleteRequirementDto,
    ipAddress: string | null,
  ) {
    const profile = await this.caregiverProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');

    const application = await this.applicationsRepo.findByRequirementAndProfile(requirementId, profile.id);
    if (!application || application.status !== JobApplicationStatus.ACCEPTED) {
      throw new AppException('JOB_008');
    }

    const closeReason = dto.close_reason?.trim() || CaregiverCloseReason.NO_REASON;

    let stillAssigned = false;
    await this.db.withTransaction(async (client) => {
      await this.applicationsRepo.markCompleted(application.id, closeReason, client);
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
      afterValue: {
        status: 'completed',
        verification_status: stillAssigned ? 'assigned' : 'available',
        close_reason: closeReason,
      },
      ipAddress,
    });

    return { message: 'Requirement marked complete', verification_status: stillAssigned ? 'assigned' : 'available' };
  }

  // ---- Admin-facing ----

  async listRequirementsForAdmin(query: ListOrganisationRequirementsQueryDto) {
    const { items, total } = await this.requirementsRepo.listForAdmin(
      {
        status: query.status,
        posted_by: query.posted_by,
        organisation_type: query.organisation_type,
        city: query.city,
        search: query.search,
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

  async getRequirementDetailForAdmin(id: string) {
    const requirement = await this.requirementsRepo.findById(id);
    if (!requirement) throw new AppException('GEN_002');
    const [applications, organisation] = await Promise.all([
      this.applicationsRepo.findByRequirementId(id),
      this.organisationProfilesRepo.findByUserIdWithPhone(requirement.posted_by),
    ]);
    return {
      ...requirement,
      applications,
      organisation_name: organisation?.organisation_name ?? null,
      organisation_type: organisation?.organisation_type ?? null,
      city: organisation?.city ?? null,
      area: organisation?.area ?? null,
      contact_person_name: organisation?.contact_person_name ?? null,
      organisation_phone: organisation?.phone ?? null,
    };
  }

  /** Admin can edit any org-owned field on a requirement — the same fields
   *  the org itself can edit via editRequirement above — reversing the
   *  original "admin's entire role is a pure approve/reject click, no
   *  fields at all" design on explicit follow-up request. [dto] is a
   *  partial update (every field optional): anything omitted keeps its
   *  existing value, so a bare/empty body still works as a pure approve,
   *  same as the old approveRequirement this replaces. Saving from
   *  pending_review (or a previously-closed requirement) also activates it
   *  and re-broadcasts the "New Organisation Opening" push — same
   *  repost-on-save behavior JobsService.updateJob has for jobs; saving an
   *  already-active requirement just persists the field changes, no
   *  re-broadcast. Unlike the org's own editRequirement, this is NOT
   *  blocked by an existing application (JOB_014) — admin may need to fix
   *  a field after caregivers have already applied. */
  async adminEditRequirement(
    adminId: string,
    id: string,
    dto: AdminEditOrganisationRequirementDto,
    ipAddress: string | null,
  ) {
    const existing = await this.requirementsRepo.findById(id);
    if (!existing) throw new AppException('GEN_002');

    const typeOfNurse = dto.type_of_nurse ?? existing.type_of_nurse;
    const typeOfNurseOther =
      typeOfNurse === TypeOfNurse.OTHERS
        ? (dto.type_of_nurse_other ?? existing.type_of_nurse_other ?? undefined)
        : undefined;
    this.validateTypeOfNurseOther(typeOfNurse, typeOfNurseOther);

    let requirement = await this.requirementsRepo.updateOwnFields(id, {
      type_of_nurse: typeOfNurse,
      type_of_nurse_other: typeOfNurse === TypeOfNurse.OTHERS ? (typeOfNurseOther ?? null) : null,
      accommodation_provided: dto.accommodation_provided ?? existing.accommodation_provided,
      food_provided: dto.food_provided ?? existing.food_provided,
      special_skills: dto.special_skills !== undefined ? dto.special_skills : existing.special_skills,
      number_of_vacancies: dto.number_of_vacancies ?? existing.number_of_vacancies,
      preferred_gender: dto.preferred_gender !== undefined ? dto.preferred_gender : existing.preferred_gender,
      duration_type: dto.duration_type ?? existing.duration_type!,
    });

    if (existing.status !== JobStatus.ACTIVE) {
      requirement = await this.requirementsRepo.activate(id);
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
      beforeValue: { type_of_nurse: existing.type_of_nurse, status: existing.status },
      afterValue: { type_of_nurse: requirement.type_of_nurse, status: requirement.status },
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
