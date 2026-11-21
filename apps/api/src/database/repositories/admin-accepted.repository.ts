import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

/** One caregiver who was accepted onto a job or organisation requirement, seen from
 *  admin's side, with what has happened since. `status` is the application's CURRENT
 *  status: accepted (still on it), completed (the caregiver closed duty), rejected
 *  (accepted, then let go or declined later) or applied (re-applied afterwards). */
export interface AcceptedItem {
  kind: 'job' | 'organisation_requirement';
  application_id: string;
  status: 'accepted' | 'completed' | 'rejected' | 'applied';
  /** When the latest acceptance happened (a re-acceptance overwrites it). */
  accepted_at: Date;
  caregiver_profile_id: string;
  caregiver_number: number | null;
  caregiver_name: string;
  caregiver_phone: string;
  admin_job_number: number | null;
  patient_job_number: number | null;
  requirement_number: number | null;
  poster_name: string | null;
  poster_phone: string | null;
  poster_role: string | null;
  poster_number: number | null;
  /** Who accepted — only known while the application is still accepted/completed
   *  (a later rejection overwrites decided_by with the rejecter). */
  accepted_by_name: string | null;
  accepted_by_role: string | null;
  /** What the patient/family or organisation agreed: rupees, 'daily'|'monthly', start date. */
  agreed_salary: number | null;
  agreed_salary_unit: 'daily' | 'monthly' | null;
  agreed_start_date: string | null;
}

export interface AcceptedFilters {
  status?: 'accepted' | 'completed' | 'rejected' | 'applied';
  search?: string;
}

const JOB_SELECT = `
  SELECT 'job' AS kind, ja.id AS application_id, ja.status, ja.decided_by, ja.accepted_at,
         ja.profile_id, j.admin_job_number, j.patient_job_number, NULL::int AS requirement_number,
         pu.full_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
         ip.patient_number AS poster_number,
         ja.agreed_salary, ja.agreed_salary_unit, ja.agreed_start_date::text AS agreed_start_date
  FROM job_applications ja
  JOIN jobs j ON j.id = ja.job_id
  LEFT JOIN users pu ON pu.id = j.posted_by
  LEFT JOIN individual_profiles ip ON ip.user_id = j.posted_by
  WHERE ja.accepted_at IS NOT NULL`;

const REQUIREMENT_SELECT = `
  SELECT 'organisation_requirement' AS kind, oa.id AS application_id, oa.status, oa.decided_by, oa.accepted_at,
         oa.profile_id, NULL::int AS admin_job_number, NULL::int AS patient_job_number,
         r.requirement_number,
         op.organisation_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
         op.org_number AS poster_number,
         oa.agreed_salary, oa.agreed_salary_unit, oa.agreed_start_date::text AS agreed_start_date
  FROM organisation_requirement_applications oa
  JOIN organisation_requirements r ON r.id = oa.requirement_id
  LEFT JOIN users pu ON pu.id = r.posted_by
  LEFT JOIN organisation_profiles op ON op.user_id = r.posted_by
  WHERE oa.accepted_at IS NOT NULL`;

const ITEMS_CTE = `
  WITH raw AS (${JOB_SELECT} UNION ALL ${REQUIREMENT_SELECT}),
  items AS (
    SELECT raw.kind, raw.application_id, raw.status, raw.accepted_at,
           cp.id AS caregiver_profile_id, cp.caregiver_number,
           cu.full_name AS caregiver_name, cu.phone AS caregiver_phone,
           raw.admin_job_number, raw.patient_job_number, raw.requirement_number,
           raw.poster_name, raw.poster_phone, raw.poster_role, raw.poster_number,
           CASE WHEN raw.status IN ('accepted', 'completed') THEN du.full_name END AS accepted_by_name,
           CASE WHEN raw.status IN ('accepted', 'completed') THEN du.role END AS accepted_by_role,
           raw.agreed_salary, raw.agreed_salary_unit, raw.agreed_start_date
    FROM raw
    JOIN caregiver_profiles cp ON cp.id = raw.profile_id
    JOIN users cu ON cu.id = cp.user_id
    LEFT JOIN users du ON du.id = raw.decided_by
  )`;

/** Escapes LIKE wildcards so a search for "50%" matches literally. */
const escapeLike = (value: string): string => value.split('\\').join('\\\\').split('%').join('\\%').split('_').join('\\_');

@Injectable()
export class AdminAcceptedRepository {
  constructor(private readonly db: DatabaseService) {}

  async list(filters: AcceptedFilters, page: ListPage): Promise<{ items: AcceptedItem[]; total: number }> {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (filters.status) {
      params.push(filters.status);
      conditions.push(`status = $${params.length}`);
    }
    if (filters.search) {
      params.push(`%${escapeLike(filters.search)}%`);
      const p = `$${params.length}`;
      conditions.push(
        `(caregiver_name ILIKE ${p} OR caregiver_phone ILIKE ${p} OR poster_name ILIKE ${p} OR poster_phone ILIKE ${p}
          OR ('NUR-' || caregiver_number::text) ILIKE ${p}
          OR ('PAT-' || poster_number::text) ILIKE ${p} OR ('ORG-' || poster_number::text) ILIKE ${p}
          OR ('PAT-JOB-' || patient_job_number::text) ILIKE ${p} OR ('ADMIN-JOB-' || admin_job_number::text) ILIKE ${p}
          OR ('ORG-JOB-' || requirement_number::text) ILIKE ${p})`,
      );
    }
    const clause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const [list, count] = await Promise.all([
      this.db.query<AcceptedItem>(
        `${ITEMS_CTE} SELECT * FROM items ${clause}
         ORDER BY accepted_at DESC, application_id
         LIMIT $${listParams.length - 1} OFFSET $${listParams.length}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`${ITEMS_CTE} SELECT COUNT(*) FROM items ${clause}`, params),
    ]);
    return { items: list.rows, total: Number(count.rows[0].count) };
  }
}
