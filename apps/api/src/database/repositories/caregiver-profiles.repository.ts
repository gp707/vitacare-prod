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
  advanced_details_completed: boolean;
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
  salary: string | null;
  terms_accepted: boolean;
  verification_status: VerificationStatus;
  rejection_message: string | null;
  advanced_details_completed: boolean;
  has_pending_edits: boolean;
  submitted_at: Date | null;
  verified_at: Date | null;
  created_at: Date;
}

export interface CreateCaregiverProfileInput {
  user_id: string;
  gender: Gender;
  age: number;
  religion: Religion;
}

export interface UpdateBasicProfileInput {
  age: number;
}

/** Admin partial-edit — only the keys present (not undefined) are written. */
export interface AdminUpdateProfileInput {
  gender?: Gender;
  age?: number;
  highest_qualification?: Qualification;
  religion?: Religion;
}

/** Caregiver self-edit of advanced fields, any subset — same partial-write
 *  semantics as AdminUpdateProfileInput, but always flags has_pending_edits
 *  and never touches verification_status (unlike the one-time submission).
 *  religion is intentionally absent — locked from self-edit once set. */
export interface EditAdvancedProfileInput {
  highest_qualification?: Qualification;
}

export interface UpdateAdvancedProfileInput {
  highest_qualification: Qualification;
}

const FULL_PROFILE_COLUMNS = `
  cp.id, cp.user_id, u.full_name, u.phone, u.email, cp.gender, cp.age,
  cp.selfie_photo_url, cp.highest_qualification, cp.qualification_document_url,
  cp.aadhaar_document_url, cp.other_document_urls, cp.religion, cp.salary,
  cp.terms_accepted,
  cp.verification_status, cp.rejection_message, cp.advanced_details_completed,
  cp.has_pending_edits, cp.submitted_at, cp.verified_at, cp.created_at
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
      `INSERT INTO caregiver_profiles (user_id, gender, age, religion)
       VALUES ($1, $2, $3, $4)
       RETURNING id, user_id, gender, age, verification_status, advanced_details_completed`,
      [input.user_id, input.gender, input.age, input.religion],
    );
    return result.rows[0];
  }

  async findByUserId(userId: string): Promise<CaregiverProfileRecord | null> {
    const result = await this.db.query<CaregiverProfileRecord>(
      `SELECT id, user_id, gender, age, verification_status, advanced_details_completed
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

  async updateBasic(
    profileId: string,
    input: UpdateBasicProfileInput,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE caregiver_profiles
       SET age = $2, has_pending_edits = true, updated_at = NOW()
       WHERE id = $1`,
      [profileId, input.age],
    );
  }

  async updateAdvanced(
    profileId: string,
    input: UpdateAdvancedProfileInput,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE caregiver_profiles
       SET highest_qualification = $2,
           terms_accepted = true,
           advanced_details_completed = true,
           verification_status = 'pending_verification',
           submitted_at = NOW(),
           rejection_message = NULL,
           updated_at = NOW()
       WHERE id = $1`,
      [profileId, input.highest_qualification],
    );
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
  async editAdvancedFields(profileId: string, input: EditAdvancedProfileInput): Promise<void> {
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

  /** Used when a self-edit only touches preferred_cities (a separate
   *  junction table, not a column here) — editAdvancedFields is a no-op for
   *  an all-undefined input, so this is the fallback that still flags the
   *  edit for admin visibility. */
  async flagPendingEdits(profileId: string): Promise<void> {
    await this.db.query(
      'UPDATE caregiver_profiles SET has_pending_edits = true, updated_at = NOW() WHERE id = $1',
      [profileId],
    );
  }

  /** Sends a verified/available-or-unavailable caregiver back for re-review
   *  after an identity-sensitive change (phone number, Aadhaar re-upload).
   *  Callers are responsible for only invoking this when eligible — this
   *  method itself doesn't check the current status. */
  async markForReReview(profileId: string): Promise<void> {
    await this.db.query(
      `UPDATE caregiver_profiles
       SET verification_status = 'pending_verification',
           submitted_at = NOW(),
           has_pending_edits = true,
           updated_at = NOW()
       WHERE id = $1`,
      [profileId],
    );
  }

  async updateSalary(profileId: string, salary: number, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      'UPDATE caregiver_profiles SET salary = $2, updated_at = NOW() WHERE id = $1',
      [profileId, salary],
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
