import { Module } from '@nestjs/common';
import { ScopeOfWorkController } from './scope-of-work.controller';
import { AdminScopeOfWorkController } from './admin-scope-of-work.controller';
import { ScopeOfWorkService } from './scope-of-work.service';

@Module({
  controllers: [ScopeOfWorkController, AdminScopeOfWorkController],
  providers: [ScopeOfWorkService],
})
export class ScopeOfWorkModule {}
