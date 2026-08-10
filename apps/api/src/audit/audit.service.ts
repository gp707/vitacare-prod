import { Injectable, Logger } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { DatabaseService } from '../database/database.service';

export interface AuditLogEntry {
  userId: string | null;
  targetUserId?: string | null;
  action: AuditAction;
  entityType: string;
  entityId?: string | null;
  beforeValue?: Record<string, unknown> | null;
  afterValue?: Record<string, unknown> | null;
  ipAddress?: string | null;
}

/**
 * Append-only audit trail (SPEC.md section 11). Writes are best-effort: a
 * failed audit insert is logged but never thrown, so it can't take down the
 * mutating request it's describing.
 */
@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly db: DatabaseService) {}

  async log(entry: AuditLogEntry): Promise<void> {
    try {
      await this.db.query(
        `INSERT INTO audit_logs
           (user_id, target_user_id, action, entity_type, entity_id, before_value, after_value, ip_address)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          entry.userId,
          entry.targetUserId ?? null,
          entry.action,
          entry.entityType,
          entry.entityId ?? null,
          entry.beforeValue ? JSON.stringify(entry.beforeValue) : null,
          entry.afterValue ? JSON.stringify(entry.afterValue) : null,
          entry.ipAddress ?? null,
        ],
      );
    } catch (error) {
      this.logger.error(`Failed to write audit log entry (action: "${entry.action}")`, error);
    }
  }
}
