import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export type FeedbackAuthorRole = 'individual' | 'caregiver';

export interface FeedbackRow {
  author_role: FeedbackAuthorRole;
  author_user_id: string;
  about_user_id: string;
  rating: number;
  comment: string | null;
  created_at: Date;
}

export interface FeedbackAdminItem {
  id: string;
  author_role: FeedbackAuthorRole;
  rating: number;
  comment: string | null;
  created_at: Date;
  job_id: string;
  admin_job_number: number | null;
  patient_job_number: number | null;
  caregiver_number: number | null;
  caregiver_profile_id: string;
  caregiver_name: string | null;
  patient_number: number | null;
  patient_user_id: string | null;
  patient_name: string | null;
}

export interface FeedbackAdminFilters {
  author_role?: FeedbackAuthorRole;
  rating?: number;
  search?: string;
}

/** Escapes LIKE wildcards so a search for "50%" matches literally. */
const escapeLike = (value: string): string => value.split('\\').join('\\\\').split('%').join('\\%').split('_').join('\\_');

/** Feedback between a patient/family and a caregiver (migration 096): one row per
 *  person per engagement, write once and final. */
@Injectable()
export class EngagementFeedbackRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Both directions for one engagement (at most two rows). */
  async listByApplication(applicationId: string): Promise<FeedbackRow[]> {
    const result = await this.db.query<FeedbackRow>(
      `SELECT author_role, author_user_id, about_user_id, rating, comment, created_at
       FROM engagement_feedback WHERE application_id = $1`,
      [applicationId],
    );
    return result.rows;
  }

  /** Saves a feedback. False when this person already left one for this engagement. */
  async insert(row: {
    application_id: string;
    author_role: FeedbackAuthorRole;
    author_user_id: string;
    about_user_id: string;
    rating: number;
    comment: string | null;
  }): Promise<boolean> {
    const result = await this.db.query(
      `INSERT INTO engagement_feedback (application_id, author_role, author_user_id, about_user_id, rating, comment)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (application_id, author_role) DO NOTHING
       RETURNING id`,
      [row.application_id, row.author_role, row.author_user_id, row.about_user_id, row.rating, row.comment],
    );
    return (result.rowCount ?? 0) > 0;
  }

  async listForAdmin(filters: FeedbackAdminFilters, page: ListPage): Promise<{ items: FeedbackAdminItem[]; total: number }> {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (filters.author_role) {
      params.push(filters.author_role);
      conditions.push(`f.author_role = $${params.length}`);
    }
    if (filters.rating) {
      params.push(filters.rating);
      conditions.push(`f.rating = $${params.length}`);
    }
    if (filters.search) {
      params.push(`%${escapeLike(filters.search)}%`);
      const p = `$${params.length}`;
      conditions.push(
        `(cu.full_name ILIKE ${p} OR cu.phone ILIKE ${p} OR pu.full_name ILIKE ${p} OR pu.phone ILIKE ${p}
          OR ('NUR-' || cp.caregiver_number::text) ILIKE ${p} OR ('PAT-' || ip.patient_number::text) ILIKE ${p}
          OR f.comment ILIKE ${p})`,
      );
    }
    const clause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const joins = `
      FROM engagement_feedback f
      JOIN job_applications ja ON ja.id = f.application_id
      JOIN jobs j ON j.id = ja.job_id
      JOIN caregiver_profiles cp ON cp.id = ja.profile_id
      JOIN users cu ON cu.id = cp.user_id
      LEFT JOIN users pu ON pu.id = j.posted_by
      LEFT JOIN individual_profiles ip ON ip.user_id = j.posted_by`;
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const [list, count] = await Promise.all([
      this.db.query<FeedbackAdminItem>(
        `SELECT f.id, f.author_role, f.rating, f.comment, f.created_at, j.id AS job_id,
                j.admin_job_number, j.patient_job_number,
                cp.caregiver_number, cp.id AS caregiver_profile_id, cu.full_name AS caregiver_name,
                ip.patient_number, pu.id AS patient_user_id, pu.full_name AS patient_name
         ${joins} ${clause}
         ORDER BY f.created_at DESC
         LIMIT $${listParams.length - 1} OFFSET $${listParams.length}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) ${joins} ${clause}`, params),
    ]);
    return { items: list.rows, total: Number(count.rows[0].count) };
  }
}
