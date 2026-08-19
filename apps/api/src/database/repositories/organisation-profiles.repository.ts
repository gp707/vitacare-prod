import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';

export interface OrganisationProfileRecord {
  id: string;
  user_id: string;
  organisation_name: string;
  contact_person_name: string;
  organisation_type: string;
  city: string;
  area: string;
  is_job_posting_blocked: boolean;
  block_reason: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface CreateOrganisationProfileInput {
  organisation_name: string;
  contact_person_name: string;
  organisation_type: string;
  city: string;
  area: string;
}

/** Self-service side of an organisation account — mirrors
 *  IndividualProfilesRepository's shape. Admin's listing/block/unblock
 *  actions live in AdminOrganisationsRepository instead, same split as the
 *  individual side. */
@Injectable()
export class OrganisationProfilesRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(
    userId: string,
    input: CreateOrganisationProfileInput,
    client?: PoolClient,
  ): Promise<OrganisationProfileRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<OrganisationProfileRecord>(
      `INSERT INTO organisation_profiles (user_id, organisation_name, contact_person_name, organisation_type, city, area)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [userId, input.organisation_name, input.contact_person_name, input.organisation_type, input.city, input.area],
    );
    return result.rows[0];
  }

  async findByUserId(userId: string): Promise<OrganisationProfileRecord | null> {
    const result = await this.db.query<OrganisationProfileRecord>(
      'SELECT * FROM organisation_profiles WHERE user_id = $1',
      [userId],
    );
    return result.rows[0] ?? null;
  }
}
