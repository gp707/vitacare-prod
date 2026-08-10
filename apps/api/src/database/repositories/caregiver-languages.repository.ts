import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { Language } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

@Injectable()
export class CaregiverLanguagesRepository {
  constructor(private readonly db: DatabaseService) {}

  async createMany(profileId: string, languages: Language[], client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    const values = languages.map((_, i) => `($1, $${i + 2})`).join(', ');
    await runner.query(
      `INSERT INTO caregiver_languages (profile_id, language) VALUES ${values}`,
      [profileId, ...languages],
    );
  }

  async findByProfileId(profileId: string): Promise<Language[]> {
    const result = await this.db.query<{ language: Language }>(
      'SELECT language FROM caregiver_languages WHERE profile_id = $1',
      [profileId],
    );
    return result.rows.map((row) => row.language);
  }

  async replaceForProfile(
    profileId: string,
    languages: Language[],
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('DELETE FROM caregiver_languages WHERE profile_id = $1', [profileId]);
    await this.createMany(profileId, languages, client);
  }
}
