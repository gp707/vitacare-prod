import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { City } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

@Injectable()
export class CaregiverPreferredCitiesRepository {
  constructor(private readonly db: DatabaseService) {}

  async createMany(profileId: string, cities: City[], client?: PoolClient): Promise<void> {
    if (cities.length === 0) return;
    const runner: QueryRunner = client ?? this.db;
    const values = cities.map((_, i) => `($1, $${i + 2})`).join(', ');
    await runner.query(
      `INSERT INTO caregiver_preferred_cities (profile_id, city) VALUES ${values}`,
      [profileId, ...cities],
    );
  }

  async findByProfileId(profileId: string): Promise<City[]> {
    const result = await this.db.query<{ city: City }>(
      'SELECT city FROM caregiver_preferred_cities WHERE profile_id = $1',
      [profileId],
    );
    return result.rows.map((row) => row.city);
  }

  async replaceForProfile(profileId: string, cities: City[], client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('DELETE FROM caregiver_preferred_cities WHERE profile_id = $1', [profileId]);
    await this.createMany(profileId, cities, client);
  }
}
