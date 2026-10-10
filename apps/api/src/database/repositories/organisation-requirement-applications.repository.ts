import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { JobApplicationStatus } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';
import { MyApplicationSummary } from './jobs.repository';
import { OrganisationRequirementWithOrg } from './organisation-requirements.repository';

export interface OrganisationRequirementApplicationRecord {
  id: string;
  requirement_id: string;
  profile_id: string;
  status: JobApplicationStatus;
  decided_by: string | null;
  applied_at: Date | null;
  accepted_at: Date | null;
  rejected_at: Date | null;
  completed_at: Date | null;
  reapplied_at: Date | null;
  decline_reason: string | null;
  close_reason: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface OrganisationRequirementApplicationWithCaregiver
  extends OrganisationRequirementApplicationRecord {
  full_name: string;
  phone: string;
  decided_by_name: string | null;
}

/** An organisation requirement the caregiver is (or was) accepted onto —
 *  GET /caregiver/organisation-requirements/assigned's shape. Shaped like
 *  OrganisationRequirementWithOrg (not the bare application row) so
 *  caregiver-app can render it with the exact same card it uses for the
 *  browse list — see JobAssignedRecord for the identical pattern on the
 *  jobs side. my_application is never null here (the query only returns
 *  rows the caregiver has an accepted/completed application for).
 *  organisation_phone mirrors jobs' own job_poster.phone — deliberately
 *  scoped to this one endpoint only, never the browse list, since contact
 *  info is only shared once there's an actual accepted engagement. */
export interface OrganisationRequirementAssignedRecord extends OrganisationRequirementWithOrg {
  my_application: MyApplicationSummary;
  organisation_phone: string;
}

/** Mirrors JobApplicationsRepository exactly, against
 *  organisation_requirement_applications instead of job_applications — see
 *  "NurseNow" in CLAUDE.md for why this is a separate table. */
@Injectable()
export class OrganisationRequirementApplicationsRepository {
  constructor(private readonly db: DatabaseService) {}

  async upsert(
    requirementId: string,
    profileId: string,
    status: JobApplicationStatus,
  ): Promise<OrganisationRequirementApplicationRecord> {
    if (status === JobApplicationStatus.APPLIED) {
      // Mirrors JobApplicationsRepository.upsert's re-apply cycle exactly —
      // deliberately does NOT clear accepted_at/rejected_at/completed_at/
      // decided_by/decline_reason/close_reason from the previous cycle,
      // so both the caregiver and the org can still see the full prior
      // history (who decided what, when, and why) instead of it vanishing
      // the moment a new cycle starts — status alone is the authoritative
      // "current state" column everywhere else in the codebase, these are
      // read only for display. Stamps reapplied_at as a "this row was
      // overwritten by a fresh apply" marker when the row being
      // overwritten was 'rejected' or 'completed'.
      const result = await this.db.query<OrganisationRequirementApplicationRecord>(
        `INSERT INTO organisation_requirement_applications (requirement_id, profile_id, status, applied_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (requirement_id, profile_id)
         DO UPDATE SET
           status = EXCLUDED.status,
           applied_at = NOW(),
           reapplied_at = CASE
             WHEN organisation_requirement_applications.status IN ('rejected', 'completed') THEN NOW()
             ELSE organisation_requirement_applications.reapplied_at
           END,
           updated_at = NOW()
         RETURNING *`,
        [requirementId, profileId, status],
      );
      return result.rows[0];
    }

    const result = await this.db.query<OrganisationRequirementApplicationRecord>(
      `INSERT INTO organisation_requirement_applications (requirement_id, profile_id, status, rejected_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (requirement_id, profile_id)
       DO UPDATE SET status = EXCLUDED.status, rejected_at = NOW(), updated_at = NOW()
       RETURNING *`,
      [requirementId, profileId, status],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<OrganisationRequirementApplicationRecord | null> {
    const result = await this.db.query<OrganisationRequirementApplicationRecord>(
      'SELECT * FROM organisation_requirement_applications WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  /** Accepting (including "Accept Anyway" on a previously-rejected/
   *  completed application) deliberately never touches decline_reason —
   *  an accept call never carries a reason in the first place, and
   *  overwriting it to NULL would destroy the prior rejection's reason
   *  from the timeline the moment it's accepted anyway; only a reject
   *  call ever sets decline_reason. Mirrors JobApplicationsRepository.
   *  decide() exactly. */
  async decide(
    id: string,
    status: JobApplicationStatus,
    actorId: string,
    client?: PoolClient,
    declineReason?: string,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    if (status === JobApplicationStatus.REJECTED) {
      await runner.query(
        `UPDATE organisation_requirement_applications
         SET status = $2, decided_by = $3, decline_reason = $4, rejected_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [id, status, actorId, declineReason ?? null],
      );
      return;
    }
    await runner.query(
      `UPDATE organisation_requirement_applications
       SET status = $2, decided_by = $3, accepted_at = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [id, status, actorId],
    );
  }

  /** Used by OrganisationRequirementsService.editRequirement (JOB_014) —
   *  deliberately ANY application at all (applied/accepted/rejected/
   *  completed), not just an active one. Unlike the jobs pipeline's
   *  equivalent (JobApplicationsRepository.hasActiveApplicationForJob,
   *  which only counts applied/accepted), an organisation requirement
   *  locks for editing the moment any caregiver has ever responded to it —
   *  a deliberate stricter rule requested specifically for Organisation. */
  async hasAnyApplicationForRequirement(requirementId: string): Promise<boolean> {
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*) FROM organisation_requirement_applications WHERE requirement_id = $1`,
      [requirementId],
    );
    return Number(result.rows[0].count) > 0;
  }

  async findByRequirementAndProfile(
    requirementId: string,
    profileId: string,
  ): Promise<OrganisationRequirementApplicationRecord | null> {
    const result = await this.db.query<OrganisationRequirementApplicationRecord>(
      'SELECT * FROM organisation_requirement_applications WHERE requirement_id = $1 AND profile_id = $2',
      [requirementId, profileId],
    );
    return result.rows[0] ?? null;
  }

  /** closeReason defaults to NO_REASON in the service layer before this is
   *  called, so it's always a real value here, never null/undefined. */
  async markCompleted(id: string, closeReason: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirement_applications SET status = 'completed', completed_at = NOW(), close_reason = $2, updated_at = NOW() WHERE id = $1`,
      [id, closeReason],
    );
  }

  async countAcceptedByProfileId(profileId: string, client?: PoolClient): Promise<number> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<{ count: string }>(
      `SELECT COUNT(*) FROM organisation_requirement_applications WHERE profile_id = $1 AND status = 'accepted'`,
      [profileId],
    );
    return Number(result.rows[0].count);
  }

  async findByRequirementId(requirementId: string): Promise<OrganisationRequirementApplicationWithCaregiver[]> {
    const result = await this.db.query<OrganisationRequirementApplicationWithCaregiver>(
      `SELECT ora.*, u.full_name, u.phone, decider.full_name AS decided_by_name
       FROM organisation_requirement_applications ora
       JOIN caregiver_profiles cp ON cp.id = ora.profile_id
       JOIN users u ON u.id = cp.user_id
       LEFT JOIN users decider ON decider.id = ora.decided_by
       WHERE ora.requirement_id = $1
       ORDER BY ora.updated_at DESC`,
      [requirementId],
    );
    return result.rows;
  }

  async findAssignedByProfileId(profileId: string): Promise<OrganisationRequirementAssignedRecord[]> {
    const result = await this.db.query<OrganisationRequirementAssignedRecord>(
      `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area, u.phone AS organisation_phone,
         jsonb_build_object(
           'status', ora.status,
           'applied_at', ora.applied_at,
           'accepted_at', ora.accepted_at,
           'rejected_at', ora.rejected_at,
           'completed_at', ora.completed_at,
           'reapplied_at', ora.reapplied_at,
           'decided_by_admin', ora.decided_by IS NOT NULL,
           'decline_reason', ora.decline_reason,
           'close_reason', ora.close_reason
         ) AS my_application
       FROM organisation_requirement_applications ora
       JOIN organisation_requirements r ON r.id = ora.requirement_id
       JOIN organisation_profiles op ON op.user_id = r.posted_by
       JOIN users u ON u.id = r.posted_by
       WHERE ora.profile_id = $1 AND ora.status IN ('accepted', 'completed')
       ORDER BY ora.updated_at ASC`,
      [profileId],
    );
    return result.rows;
  }

  /** Mirrors JobsRepository.listHistoryForCaregiver — every application
   *  this caregiver has ever made on an organisation requirement,
   *  regardless of its current status, so a rejected/withdrawn
   *  application doesn't vanish once the requirement itself closes. */
  async findHistoryByProfileId(profileId: string): Promise<OrganisationRequirementAssignedRecord[]> {
    const result = await this.db.query<OrganisationRequirementAssignedRecord>(
      `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area, u.phone AS organisation_phone,
         jsonb_build_object(
           'status', ora.status,
           'applied_at', ora.applied_at,
           'accepted_at', ora.accepted_at,
           'rejected_at', ora.rejected_at,
           'completed_at', ora.completed_at,
           'reapplied_at', ora.reapplied_at,
           'decided_by_admin', ora.decided_by IS NOT NULL,
           'decline_reason', ora.decline_reason,
           'close_reason', ora.close_reason
         ) AS my_application
       FROM organisation_requirement_applications ora
       JOIN organisation_requirements r ON r.id = ora.requirement_id
       JOIN organisation_profiles op ON op.user_id = r.posted_by
       JOIN users u ON u.id = r.posted_by
       WHERE ora.profile_id = $1
       ORDER BY ora.updated_at DESC`,
      [profileId],
    );
    return result.rows;
  }
}
