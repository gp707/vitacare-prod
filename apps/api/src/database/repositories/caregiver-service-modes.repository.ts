import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { ServiceMode } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

/** Read-only from the caregiver side — service modes are admin-assigned (Phase 3). */
@Injectable()
export class CaregiverServiceModesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByProfileId(profileId: string): Promise<ServiceMode[]> {
    const result = await this.db.query<{ service_mode: ServiceMode }>(
      'SELECT service_mode FROM caregiver_service_modes WHERE profile_id = $1',
      [profileId],
    );
    return result.rows.map((row) => row.service_mode);
  }

  async replaceForProfile(
    profileId: string,
    modes: ServiceMode[],
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('DELETE FROM caregiver_service_modes WHERE profile_id = $1', [profileId]);
    const values = modes.map((_, i) => `($1, $${i + 2})`).join(', ');
    await runner.query(
      `INSERT INTO caregiver_service_modes (profile_id, service_mode) VALUES ${values}`,
      [profileId, ...modes],
    );
  }
}
