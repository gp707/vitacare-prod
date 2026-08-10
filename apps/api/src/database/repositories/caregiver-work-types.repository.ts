import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { WorkType } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

/** Read-only from the caregiver side — work types are admin-assigned (Phase 3). */
@Injectable()
export class CaregiverWorkTypesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByProfileId(profileId: string): Promise<WorkType[]> {
    const result = await this.db.query<{ work_type: WorkType }>(
      'SELECT work_type FROM caregiver_work_types WHERE profile_id = $1',
      [profileId],
    );
    return result.rows.map((row) => row.work_type);
  }

  async replaceForProfile(
    profileId: string,
    workTypes: WorkType[],
    assignedBy: string,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('DELETE FROM caregiver_work_types WHERE profile_id = $1', [profileId]);
    const values = workTypes.map((_, i) => `($1, $${i + 3}, $2)`).join(', ');
    await runner.query(
      `INSERT INTO caregiver_work_types (profile_id, work_type, assigned_by) VALUES ${values}`,
      [profileId, assignedBy, ...workTypes],
    );
  }
}
