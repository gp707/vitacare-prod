import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { UserRole } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface UserRecord {
  id: string;
  email: string | null;
  phone: string;
  password_hash: string | null;
  code_hash: string | null;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  fcm_token: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface CreateUserInput {
  phone: string;
  full_name: string;
  role: UserRole;
  email?: string | null;
  password_hash?: string | null;
}

@Injectable()
export class UsersRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByPhone(phone: string): Promise<UserRecord | null> {
    const result = await this.db.query<UserRecord>('SELECT * FROM users WHERE phone = $1', [
      phone,
    ]);
    return result.rows[0] ?? null;
  }

  async findByEmail(email: string): Promise<UserRecord | null> {
    const result = await this.db.query<UserRecord>('SELECT * FROM users WHERE email = $1', [
      email,
    ]);
    return result.rows[0] ?? null;
  }

  async findById(id: string): Promise<UserRecord | null> {
    const result = await this.db.query<UserRecord>('SELECT * FROM users WHERE id = $1', [id]);
    return result.rows[0] ?? null;
  }

  async create(input: CreateUserInput): Promise<UserRecord> {
    const result = await this.db.query<UserRecord>(
      `INSERT INTO users (phone, full_name, role, email, password_hash)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [input.phone, input.full_name, input.role, input.email ?? null, input.password_hash ?? null],
    );
    return result.rows[0];
  }

  async updateFullName(userId: string, fullName: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('UPDATE users SET full_name = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      fullName,
    ]);
  }

  async updatePhone(userId: string, phone: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('UPDATE users SET phone = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      phone,
    ]);
  }

  async updateCodeHash(userId: string, codeHash: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query('UPDATE users SET code_hash = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      codeHash,
    ]);
  }

  async updateFcmToken(userId: string, token: string): Promise<void> {
    await this.db.query('UPDATE users SET fcm_token = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      token,
    ]);
  }

  async listCaregiverFcmTokens(): Promise<string[]> {
    const result = await this.db.query<{ fcm_token: string }>(
      `SELECT fcm_token FROM users WHERE role = 'caregiver' AND fcm_token IS NOT NULL`,
    );
    return result.rows.map((row) => row.fcm_token);
  }

  /** Used by the daily 8 AM availability-reminder push — targets only
   *  caregivers whose status is one of the given verification statuses
   *  (available/unavailable), unlike listCaregiverFcmTokens which is an
   *  unfiltered broadcast to every caregiver. */
  async listCaregiverFcmTokensByStatus(statuses: string[]): Promise<string[]> {
    const result = await this.db.query<{ fcm_token: string }>(
      `SELECT u.fcm_token FROM users u
       JOIN caregiver_profiles cp ON cp.user_id = u.id
       WHERE u.role = 'caregiver' AND u.fcm_token IS NOT NULL AND cp.verification_status = ANY($1::text[])`,
      [statuses],
    );
    return result.rows.map((row) => row.fcm_token);
  }

  async listAdmins(): Promise<UserRecord[]> {
    const result = await this.db.query<UserRecord>(
      `SELECT * FROM users WHERE role IN ('admin', 'super_admin') ORDER BY created_at DESC`,
    );
    return result.rows;
  }

  async updateAdmin(
    userId: string,
    input: { full_name?: string; phone?: string },
  ): Promise<UserRecord | null> {
    const result = await this.db.query<UserRecord>(
      `UPDATE users
       SET full_name = COALESCE($2, full_name), phone = COALESCE($3, phone), updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [userId, input.full_name ?? null, input.phone ?? null],
    );
    return result.rows[0] ?? null;
  }

  async setActive(userId: string, isActive: boolean): Promise<void> {
    await this.db.query('UPDATE users SET is_active = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      isActive,
    ]);
  }

  async updateRole(userId: string, role: UserRole): Promise<void> {
    await this.db.query('UPDATE users SET role = $2, updated_at = NOW() WHERE id = $1', [
      userId,
      role,
    ]);
  }

  async countSuperAdmins(): Promise<number> {
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*) as count FROM users WHERE role = 'super_admin' AND is_active = true`,
    );
    return Number(result.rows[0].count);
  }
}
