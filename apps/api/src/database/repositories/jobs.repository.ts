import { Injectable } from '@nestjs/common';
import { City, DutyType, JobStatus, Language } from '@vitacare/shared-constants';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';

export interface JobRecord {
  id: string;
  care_receiver_id: string;
  city: City;
  area: string | null;
  description: string;
  duty_type: DutyType;
  start_time: string | null;
  end_time: string | null;
  start_date: string | null;
  language: Language;
  preferred_gender: string | null;
  preferred_religion: string | null;
  status: JobStatus;
  posted_by: string;
  created_at: Date;
  updated_at: Date;
}

export interface JobWithMyApplication extends JobRecord {
  my_application_status: string | null;
}

export interface CreateJobInput {
  care_receiver_id: string;
  city: City;
  area?: string | null;
  description: string;
  duty_type: DutyType;
  start_time?: string | null;
  end_time?: string | null;
  start_date?: string | null;
  language: Language;
  preferred_gender?: string | null;
  preferred_religion?: string | null;
  posted_by: string;
}

export interface ListJobsFilters {
  status?: JobStatus;
  city?: City;
}

export interface ListPage {
  page: number;
  limit: number;
}

function buildJobsWhereClause(filters: ListJobsFilters): { clause: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];
  if (filters.status) {
    params.push(filters.status);
    conditions.push(`status = $${params.length}`);
  }
  if (filters.city) {
    params.push(filters.city);
    conditions.push(`city = $${params.length}`);
  }
  return { clause: conditions.length ? `WHERE ${conditions.join(' AND ')}` : '', params };
}

@Injectable()
export class JobsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(input: CreateJobInput, client?: PoolClient): Promise<JobRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<JobRecord>(
      `INSERT INTO jobs
         (care_receiver_id, city, area, description, duty_type, start_time, end_time,
          start_date, language, preferred_gender, preferred_religion, posted_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING *`,
      [
        input.care_receiver_id,
        input.city,
        input.area ?? null,
        input.description,
        input.duty_type,
        input.start_time ?? null,
        input.end_time ?? null,
        input.start_date ?? null,
        input.language,
        input.preferred_gender ?? null,
        input.preferred_religion ?? null,
        input.posted_by,
      ],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<JobRecord | null> {
    const result = await this.db.query<JobRecord>('SELECT * FROM jobs WHERE id = $1', [id]);
    return result.rows[0] ?? null;
  }

  async listForAdmin(
    filters: ListJobsFilters,
    page: ListPage,
  ): Promise<{ items: JobRecord[]; total: number }> {
    const { clause, params } = buildJobsWhereClause(filters);
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<JobRecord>(
        `SELECT * FROM jobs ${clause}
         ORDER BY created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM jobs ${clause}`, params),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Active jobs only, with the caregiver's own application status (if any)
   *  attached — lets the caregiver-app show "already applied" state without
   *  a second round trip. */
  async listActiveForCaregiver(
    profileId: string,
    page: ListPage,
  ): Promise<{ items: JobWithMyApplication[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<JobWithMyApplication>(
        `SELECT j.*, ja.status AS my_application_status
         FROM jobs j
         LEFT JOIN job_applications ja ON ja.job_id = j.id AND ja.profile_id = $1
         WHERE j.status = 'active'
         ORDER BY j.created_at DESC
         LIMIT $2 OFFSET $3`,
        [profileId, page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM jobs WHERE status = 'active'`),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async close(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(`UPDATE jobs SET status = 'closed', updated_at = NOW() WHERE id = $1`, [id]);
  }

  async reopen(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(`UPDATE jobs SET status = 'active', updated_at = NOW() WHERE id = $1`, [id]);
  }
}
