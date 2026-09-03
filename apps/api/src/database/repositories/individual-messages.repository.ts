import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface IndividualMessageRecord {
  id: string;
  event: string;
  icon: string;
  message: string;
  display_order: number;
  enabled: boolean;
  created_by: string | null;
  updated_by: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface CreateIndividualMessageInput {
  event: string;
  icon: string;
  message: string;
  display_order: number;
  enabled: boolean;
}

export type UpdateIndividualMessageInput = Partial<CreateIndividualMessageInput>;

/** Admin-editable content for NurseNow Individual's "Messages" tab — a
 *  real multi-row table (unlike rate_card/scope_of_work/duty_requirements,
 *  all singletons), so this repository does genuine CRUD rather than a
 *  single find()/update() pair. */
@Injectable()
export class IndividualMessagesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findEnabled(): Promise<IndividualMessageRecord[]> {
    const result = await this.db.query<IndividualMessageRecord>(
      'SELECT * FROM individual_messages WHERE enabled = true ORDER BY display_order ASC, created_at ASC',
    );
    return result.rows;
  }

  async findAll(): Promise<IndividualMessageRecord[]> {
    const result = await this.db.query<IndividualMessageRecord>(
      'SELECT * FROM individual_messages ORDER BY display_order ASC, created_at ASC',
    );
    return result.rows;
  }

  async findById(id: string): Promise<IndividualMessageRecord | null> {
    const result = await this.db.query<IndividualMessageRecord>(
      'SELECT * FROM individual_messages WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  async create(input: CreateIndividualMessageInput, adminId: string): Promise<IndividualMessageRecord> {
    const result = await this.db.query<IndividualMessageRecord>(
      `INSERT INTO individual_messages (event, icon, message, display_order, enabled, created_by, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $6)
       RETURNING *`,
      [input.event, input.icon, input.message, input.display_order, input.enabled, adminId],
    );
    return result.rows[0];
  }

  async update(
    id: string,
    input: UpdateIndividualMessageInput,
    adminId: string,
  ): Promise<IndividualMessageRecord | null> {
    const result = await this.db.query<IndividualMessageRecord>(
      `UPDATE individual_messages
       SET event = COALESCE($1, event),
           icon = COALESCE($2, icon),
           message = COALESCE($3, message),
           display_order = COALESCE($4, display_order),
           enabled = COALESCE($5, enabled),
           updated_by = $6,
           updated_at = NOW()
       WHERE id = $7
       RETURNING *`,
      [input.event, input.icon, input.message, input.display_order, input.enabled, adminId, id],
    );
    return result.rows[0] ?? null;
  }

  async delete(id: string): Promise<boolean> {
    const result = await this.db.query('DELETE FROM individual_messages WHERE id = $1', [id]);
    return (result.rowCount ?? 0) > 0;
  }
}
