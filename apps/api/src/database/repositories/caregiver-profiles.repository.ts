import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { Gender, Qualification, Religion, VerificationStatus } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface CaregiverProfileRecord {
  id: string;
  user_id: string;
  gender: Gender;
  age: number;
  verification_status: VerificationStatus;
  min_salary_per_day: number | null;
  min_salary_per_month: number | null;
}

export interface CaregiverProfileFullRecord {
  id: string;
  user_id: string;
  full_name: string;
  phone: string;
  email: string | null;
  gender: Gender;
  age: number;
  selfie_photo_url: string | null;
  highest_qualification: Qualification | null;
  qualification_document_url: string | null;
  aadhaar_document_url: string | null;
  other_document_urls: string[];
  religion: Religion | null;
  terms_accepted: boolean;
  verification_status: VerificationStatus;
  rejection_message: string | null;
  has_pending_edits: boolean;
  verified_at: Date | null;
  min_salary_per_day: number | null;
  min_salary_per_month: number | null;
  created_at: Date;
}

export interface CreateCaregiverProfileInput {
  user_id: string;
  gender: Gender;
  age: number;
  religion: Religion;
  highest_qualification: Qualification;
  terms_accepted: boolean;
}

/** Admin partial-edit — only the keys present (not undefined) are written. */
export interface AdminUpdateProfileInput {
  gender?: Gender;
  age?: number;
  highest_qualification?: Qualification;
  religion?: Religion;
}

/** Caregiver self-edit, any subset — same partial-write semantics as
 *  AdminUpdateProfileInput, but always flags has_pending_edits and never
 *  touches verification_status directly (callers handle the
 *  rejected -> pending_call auto-resubmit transition separately).
 *  full_name, gender, and religion are intentionally absent — locked from
 *  self-edit once set at registration; only admins can change them.
 *  min_salary_per_day/min_salary_per_month are job-search preferences, not
 *  profile facts — same partial-write mechanics as age/highest_qualification
 *  even though they're conceptually different. */
export interface EditProfileInput {
  age?: number;
  highest_qualification?: Qualification;
  min_salary_per_day?: number | null;
  min_salary_per_month?: number | null;
}

const FULL_PROFILE_COLUMNS = `
  cp.id, cp.user_id, u.full_name, u.phone, u.email, cp.gender, cp.age,
  cp.selfie_photo_url, cp.highest_qualification, cp.qualification_document_url,
  cp.aadhaar_document_url, cp.other_document_urls, cp.religion,
  cp.terms_accepted,
  cp.verification_status, cp.rejection_message,
  cp.has_pending_edits, cp.verified_at,
  cp.min_salary_per_day, cp.min_salary_per_month, cp.created_at
`;

@Injectable()
export class CaregiverProfilesRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(
    input: CreateCaregiverProfileInput,
    client?: PoolClient,
  ): Promise<CaregiverProfileRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<CaregiverProfileRecord>(
      `INSERT INTO caregiver_profiles (user_id, gender, age, religion, highest_qualification, terms_accepted)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, user_id, gender, age, verification_status, min_salary_per_day, min_salary_per_month`,
      [
        input.user_id,
        input.gender,
        input.age,
        input.religion,
        input.highest_qualification,
        input.terms_accepted,
      ],
    );
    return result.rows[0];
  }

  async findByUserId(userId: string): Promise<CaregiverProfileRecord | null> {
    const result = await this.db.query<CaregiverProfileRecord>(
      `SELECT id, user_id, gender, age, verification_status, min_salary_per_day, min_salary_per_month
       FROM caregiver_profiles WHERE user_id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async findFullByUserId(userId: string): Promise<CaregiverProfileFullRecord | null> {
    const result = await this.db.query<CaregiverProfileFullRecord>(
      `SELECT ${FULL_PROFILE_COLUMNS}
       FROM caregiver_profiles cp
       JOIN users u ON u.id = cp.user_id
       WHERE cp.user_id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  /** Keyed by profile id (not user id) — used when the caller only has a
   *  job_applications/organisation_requirement_applications row's
   *  profile_id in hand, e.g. an individual/organisation viewing an
   *  applicant's profile. */
  async findFullById(profileId: string): Promise<CaregiverProfileFullRecord | null> {
    const result = await this.db.query<CaregiverProfileFullRecord>(
      `SELECT ${FULL_PROFILE_COLUMNS}
       FROM caregiver_profiles cp
       JOIN users u ON u.id = cp.user_id
       WHERE cp.id = $1`,
      [profileId],
    );
    return result.rows[0] ?? null;
  }

  /** Partial update — only fields present (not undefined) on `input` are written.
   *  preferred_cities is NOT one of these fields — see CaregiverPreferredCitiesRepository. */
  async adminUpdate(
    profileId: string,
    input: AdminUpdateProfileInput,
    client?: PoolClient,
  ): Promise<void> {
    const entries = Object.entries(input).filter(([, value]) => value !== undefined);
    if (entries.length === 0) return;

    const runner: QueryRunner = client ?? this.db;
    const setClauses = entries.map(([key], i) => `${key} = $${i + 2}`);
    const values = entries.map(([, value]) => value);
    await runner.query(
      `UPDATE caregiver_profiles SET ${setClauses.join(', ')}, updated_at = NOW() WHERE id = $1`,
      [profileId, ...values],
    );
  }

  /** Partial update — only fields present (not undefined) on `input` are written.
   *  Always flags has_pending_edits; never touches verification_status. */
  async editFields(profileId: string, input: EditProfileInput): Promise<void> {
    const entries = Object.entries(input).filter(([, value]) => value !== undefined);
    if (entries.length === 0) return;

    const setClauses = entries.map(([key], i) => `${key} = $${i + 2}`);
    const values = entries.map(([, value]) => value);
    await this.db.query(
      `UPDATE caregiver_profiles
       SET ${setClauses.join(', ')}, has_pending_edits = true, updated_at = NOW()
       WHERE id = $1`,
      [profileId, ...values],
    );
  }

  /** Used when a self-edit only touches a non-column field (e.g.
   *  preferred_cities or languages, both separate junction tables) —
   *  editFields is a no-op for an all-undefined input, so this is the
   *  fallback that still flags the edit for admin visibility. */
  async flagPendingEdits(profileId: string): Promise<void> {
    await this.db.query(
      'UPDATE caregiver_profiles SET has_pending_edits = true, updated_at = NOW() WHERE id = $1',
      [profileId],
    );
  }

  /** Sends a caregiver back to pending_call for re-review: either after an
   *  identity-sensitive change (phone number, Aadhaar re-upload) while
   *  available/unavailable, or any edit at all while rejected (auto-
   *  resubmit — see CaregiverService). Callers are responsible for only
   *  invoking this when eligible — this method itself doesn't check the
   *  current status. */
  async markForReReview(profileId: string): Promise<void> {
    await this.db.query(
      `UPDATE caregiver_profiles
       SET verification_status = 'pending_call',
           rejection_message = NULL,
           has_pending_edits = true,
           updated_at = NOW()
       WHERE id = $1`,
      [profileId],
    );
  }

  /** Caregiver self-service "mark myself available" — from unavailable or
   *  assigned only (callers enforce this). Deliberately narrow: only flips
   *  verification_status, unlike the admin override which also (re-)stamps
   *  verified_at/verified_by when moving to available — this isn't a
   *  re-verification event, so those are left untouched. */
  async markAvailable(profileId: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE caregiver_profiles SET verification_status = 'available', updated_at = NOW() WHERE id = $1`,
      [profileId],
    );
  }

  async setSelfieUrl(profileId: string, path: string): Promise<void> {
    await this.db.query(
      'UPDATE caregiver_profiles SET selfie_photo_url = $2, updated_at = NOW() WHERE id = $1',
      [profileId, path],
    );
  }

  async setQualificationDocumentUrl(profileId: string, path: string): Promise<void> {
    await this.db.query(
      'UPDATE caregiver_profiles SET qualification_document_url = $2, updated_at = NOW() WHERE id = $1',
      [profileId, path],
    );
  }

  async setAadhaarDocumentUrl(profileId: string, path: string): Promise<void> {
    await this.db.query(
      'UPDATE caregiver_profiles SET aadhaar_document_url = $2, updated_at = NOW() WHERE id = $1',
      [profileId, path],
    );
  }

  async getOtherDocumentUrls(profileId: string): Promise<string[]> {
    const result = await this.db.query<{ other_document_urls: string[] }>(
      'SELECT other_document_urls FROM caregiver_profiles WHERE id = $1',
      [profileId],
    );
    return result.rows[0]?.other_document_urls ?? [];
  }

  async appendOtherDocumentUrl(profileId: string, path: string): Promise<void> {
    await this.db.query(
      `UPDATE caregiver_profiles
       SET other_document_urls = other_document_urls || to_jsonb($2::text), updated_at = NOW()
       WHERE id = $1`,
      [profileId, path],
    );
  }
}
