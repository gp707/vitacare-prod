import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DutyType } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

@Injectable()
export class CaregiverPreferredDutyTypesRepository {
  constructor(private readonly db: DatabaseService) {}

  async createMany(profileId: string, dutyTypes: DutyType[], client?: PoolClient): Promise<void> {
    if (dutyTypes.length === 0) return;
    const runner: QueryRunner = client ?? this.db;
    const values = dutyTypes.map((_, i) => `($1, $${i + 2})`).join(', ');
    await runner.query(
      `INSERT INTO caregiver_preferred_duty_types (profile_id, duty_type) VALUES ${values}`,
      [profileId, ...dutyTypes],
    );
  }

  async findByProfileId(profileId: string): Promise<DutyType[]> {
    const result = await this.db.query<{ duty_type: DutyType }>(
      'SELECT duty_type FROM caregiver_preferred_duty_types WHERE profile_id = $1',
      [profileId],
    );
    return result.rows.map((row) => row.duty_type);
  }

  async replaceForProfile(profileId: string, dutyTypes: DutyType[], client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('DELETE FROM caregiver_preferred_duty_types WHERE profile_id = $1', [profileId]);
    await this.createMany(profileId, dutyTypes, client);
  }
}
