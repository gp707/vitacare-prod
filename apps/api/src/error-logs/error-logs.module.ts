import { Module } from '@nestjs/common';
import { AdminErrorLogsController } from './admin-error-logs.controller';
import { ErrorLogsService } from './error-logs.service';

@Module({
  controllers: [AdminErrorLogsController],
  providers: [ErrorLogsService],
})
export class ErrorLogsModule {}
