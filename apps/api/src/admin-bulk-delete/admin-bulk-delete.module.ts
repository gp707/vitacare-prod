import { Module } from '@nestjs/common';
import { AdminBulkDeleteController } from './admin-bulk-delete.controller';
import { AdminBulkDeleteService } from './admin-bulk-delete.service';

@Module({
  controllers: [AdminBulkDeleteController],
  providers: [AdminBulkDeleteService],
})
export class AdminBulkDeleteModule {}
