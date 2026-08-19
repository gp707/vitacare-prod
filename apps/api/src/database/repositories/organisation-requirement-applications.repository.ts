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
  decline_reason: string | null;
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
 *  rows the caregiver has an accepted/completed application for). */
export interface OrganisationRequirementAssignedRecord extends OrganisationRequirementWithOrg {
  my_application: MyApplicationSummary;
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
      const result = await this.db.query<OrganisationRequirementApplicationRecord>(
        `INSERT INTO organisation_requirement_applications (requirement_id, profile_id, status, applied_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (requirement_id, profile_id)
         DO UPDATE SET
           status = EXCLUDED.status,
           applied_at = NOW(),
           accepted_at = NULL,
           rejected_at = NULL,
           decided_by = NULL,
           decline_reason = NULL,
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

  async decide(
    id: string,
    status: JobApplicationStatus,
    actorId: string,
    client?: PoolClient,
    declineReason?: string,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    const timestampColumn = status === JobApplicationStatus.ACCEPTED ? 'accepted_at' : 'rejected_at';
    await runner.query(
      `UPDATE organisation_requirement_applications
       SET status = $2, decided_by = $3, decline_reason = $4, ${timestampColumn} = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [id, status, actorId, declineReason ?? null],
    );
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

  async markCompleted(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirement_applications SET status = 'completed', completed_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [id],
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
      `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area,
         jsonb_build_object(
           'status', ora.status,
           'applied_at', ora.applied_at,
           'accepted_at', ora.accepted_at,
           'rejected_at', ora.rejected_at,
           'completed_at', ora.completed_at,
           'decided_by_admin', ora.decided_by IS NOT NULL
         ) AS my_application
       FROM organisation_requirement_applications ora
       JOIN organisation_requirements r ON r.id = ora.requirement_id
       JOIN organisation_profiles op ON op.user_id = r.posted_by
       WHERE ora.profile_id = $1 AND ora.status IN ('accepted', 'completed')
       ORDER BY ora.updated_at ASC`,
      [profileId],
    );
    return result.rows;
  }
}
