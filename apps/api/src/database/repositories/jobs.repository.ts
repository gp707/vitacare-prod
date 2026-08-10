import { Injectable } from '@nestjs/common';
import { City, Gender, JobStatus, Language, Religion, ServiceMode, WorkType } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface JobRecord {
  id: string;
  work_type: WorkType;
  city: City;
  description: string;
  duty_timings: ServiceMode;
  language: Language;
  gender_needed: Gender;
  religion: Religion;
  status: JobStatus;
  posted_by: string;
  created_at: Date;
  updated_at: Date;
}

export interface JobWithMyResponse extends JobRecord {
  my_response: string | null;
}

export interface CreateJobInput {
  work_type: WorkType;
  city: City;
  description: string;
  duty_timings: ServiceMode;
  language: Language;
  gender_needed: Gender;
  religion: Religion;
  posted_by: string;
}

export interface ListJobsFilters {
  status?: JobStatus;
  work_type?: WorkType;
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
  if (filters.work_type) {
    params.push(filters.work_type);
    conditions.push(`work_type = $${params.length}`);
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

  async create(input: CreateJobInput): Promise<JobRecord> {
    const result = await this.db.query<JobRecord>(
      `INSERT INTO jobs (work_type, city, description, duty_timings, language, gender_needed, religion, posted_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [
        input.work_type,
        input.city,
        input.description,
        input.duty_timings,
        input.language,
        input.gender_needed,
        input.religion,
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

  /** Active jobs only, with the caregiver's own response (if any) attached
   *  — lets the caregiver-app show "already responded" state without a
   *  second round trip. */
  async listActiveForCaregiver(
    profileId: string,
    page: ListPage,
  ): Promise<{ items: JobWithMyResponse[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<JobWithMyResponse>(
        `SELECT j.*, jr.response AS my_response
         FROM jobs j
         LEFT JOIN job_responses jr ON jr.job_id = j.id AND jr.profile_id = $1
         WHERE j.status = 'active'
         ORDER BY j.created_at DESC
         LIMIT $2 OFFSET $3`,
        [profileId, page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM jobs WHERE status = 'active'`),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async close(id: string): Promise<void> {
    await this.db.query(`UPDATE jobs SET status = 'closed', updated_at = NOW() WHERE id = $1`, [id]);
  }
}
