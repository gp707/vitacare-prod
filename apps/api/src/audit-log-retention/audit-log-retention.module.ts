import { Module } from '@nestjs/common';
import { AdminAuditLogRetentionController } from './admin-audit-log-retention.controller';
import { AuditLogRetentionService } from './audit-log-retention.service';

@Module({
  controllers: [AdminAuditLogRetentionController],
  providers: [AuditLogRetentionService],
})
export class AuditLogRetentionModule {}
