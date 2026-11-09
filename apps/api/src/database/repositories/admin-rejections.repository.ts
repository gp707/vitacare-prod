import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

/** One "someone said no" event on a job or organisation requirement, seen from
 *  admin's side. `event`:
 *   - caregiver_declined: caregiver rejected / withdrew (no reason is collected
 *     for this one — `reason` is always null);
 *   - poster_rejected: the patient, organisation or an admin rejected the
 *     caregiver (`reason` is the free-text decline_reason);
 *   - caregiver_closed: caregiver ended an accepted engagement (`reason` is the
 *     fixed close_reason key). */
export type RejectionEvent = 'caregiver_declined' | 'poster_rejected' | 'caregiver_closed';

export interface RejectionItem {
  kind: 'job' | 'organisation_requirement';
  application_id: string;
  event: RejectionEvent;
  occurred_at: Date;
  reason: string | null;
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
  decided_by_name: string | null;
  decided_by_role: string | null;
}

export interface RejectionFilters {
  direction?: 'caregiver' | 'poster';
  search?: string;
}

const JOB_SELECT = `
  SELECT 'job' AS kind, ja.id AS application_id, ja.status, ja.decided_by,
         ja.rejected_at, ja.completed_at, ja.decline_reason, ja.close_reason,
         ja.profile_id, j.admin_job_number, j.patient_job_number, NULL::int AS requirement_number,
         pu.full_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
         ip.patient_number AS poster_number
  FROM job_applications ja
  JOIN jobs j ON j.id = ja.job_id
  LEFT JOIN users pu ON pu.id = j.posted_by
  LEFT JOIN individual_profiles ip ON ip.user_id = j.posted_by
  WHERE ja.status IN ('rejected', 'completed')`;

const REQUIREMENT_SELECT = `
  SELECT 'organisation_requirement' AS kind, oa.id AS application_id, oa.status, oa.decided_by,
         oa.rejected_at, oa.completed_at, oa.decline_reason, oa.close_reason,
         oa.profile_id, NULL::int AS admin_job_number, NULL::int AS patient_job_number,
         r.requirement_number,
         op.organisation_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
         op.org_number AS poster_number
  FROM organisation_requirement_applications oa
  JOIN organisation_requirements r ON r.id = oa.requirement_id
  LEFT JOIN users pu ON pu.id = r.posted_by
  LEFT JOIN organisation_profiles op ON op.user_id = r.posted_by
  WHERE oa.status IN ('rejected', 'completed')`;

/** A rejected row with decided_by NULL is the caregiver's own decline; with
 *  decided_by set it is the poster (or an admin) rejecting the caregiver. A
 *  caregiver who declined after an earlier poster rejection keeps the old
 *  decided_by (re-applying never clears it), so that rare case reads as a
 *  poster rejection — same limitation as the caregiver app's own timeline. */
const EVENTS_CTE = `
  WITH raw AS (${JOB_SELECT} UNION ALL ${REQUIREMENT_SELECT}),
  events AS (
    SELECT raw.kind, raw.application_id,
           CASE WHEN raw.status = 'completed' THEN 'caregiver_closed'
                WHEN raw.decided_by IS NULL THEN 'caregiver_declined'
                ELSE 'poster_rejected' END AS event,
           CASE WHEN raw.status = 'completed' THEN raw.completed_at ELSE raw.rejected_at END AS occurred_at,
           CASE WHEN raw.status = 'completed' THEN raw.close_reason
                WHEN raw.decided_by IS NULL THEN NULL
                ELSE raw.decline_reason END AS reason,
           cp.id AS caregiver_profile_id, cp.caregiver_number,
           cu.full_name AS caregiver_name, cu.phone AS caregiver_phone,
           raw.admin_job_number, raw.patient_job_number, raw.requirement_number,
           raw.poster_name, raw.poster_phone, raw.poster_role, raw.poster_number,
           du.full_name AS decided_by_name, du.role AS decided_by_role
    FROM raw
    JOIN caregiver_profiles cp ON cp.id = raw.profile_id
    JOIN users cu ON cu.id = cp.user_id
    LEFT JOIN users du ON du.id = raw.decided_by
  )`;

@Injectable()
export class AdminRejectionsRepository {
  constructor(private readonly db: DatabaseService) {}

  async list(filters: RejectionFilters, page: ListPage): Promise<{ items: RejectionItem[]; total: number }> {
    const conditions: string[] = ['occurred_at IS NOT NULL'];
    const params: unknown[] = [];
    if (filters.direction === 'poster') {
      conditions.push(`event = 'poster_rejected'`);
    } else if (filters.direction === 'caregiver') {
      conditions.push(`event IN ('caregiver_declined', 'caregiver_closed')`);
    }
    if (filters.search) {
      params.push(`%${filters.search}%`);
      const p = `$${params.length}`;
      conditions.push(
        `(caregiver_name ILIKE ${p} OR caregiver_phone ILIKE ${p} OR poster_name ILIKE ${p}
          OR ('NUR-' || caregiver_number::text) ILIKE ${p} OR reason ILIKE ${p})`,
      );
    }
    const clause = `WHERE ${conditions.join(' AND ')}`;
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const [list, count] = await Promise.all([
      this.db.query<RejectionItem>(
        `${EVENTS_CTE} SELECT * FROM events ${clause}
         ORDER BY occurred_at DESC
         LIMIT $${listParams.length - 1} OFFSET $${listParams.length}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`${EVENTS_CTE} SELECT COUNT(*) FROM events ${clause}`, params),
    ]);
    return { items: list.rows, total: Number(count.rows[0].count) };
  }
}
