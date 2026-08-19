import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';

export interface IndividualProfileRecord {
  id: string;
  user_id: string;
  /** Human-friendly sequential id, e.g. patient_number 500 displays as
   *  "PAT-500" — see patientDisplayId() in packages/vitacare_shared. */
  patient_number: number;
  is_job_posting_blocked: boolean;
  block_reason: string | null;
  created_at: Date;
  updated_at: Date;
}

/** Self-service side of an individual account — mirrors
 *  CaregiverProfilesRepository's create/findByUserId shape. Admin's
 *  listing/block/unblock actions live in AdminIndividualsRepository
 *  instead, same split as CaregiverProfilesRepository/AdminCaregiversRepository. */
@Injectable()
export class IndividualProfilesRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(userId: string, client?: PoolClient): Promise<IndividualProfileRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<IndividualProfileRecord>(
      `INSERT INTO individual_profiles (user_id) VALUES ($1) RETURNING *`,
      [userId],
    );
    return result.rows[0];
  }

  async findByUserId(userId: string): Promise<IndividualProfileRecord | null> {
    const result = await this.db.query<IndividualProfileRecord>(
      'SELECT * FROM individual_profiles WHERE user_id = $1',
      [userId],
    );
    return result.rows[0] ?? null;
  }
}
