import { Module } from '@nestjs/common';
import { JobsModule } from '../jobs/jobs.module';
import { IndividualController } from './individual.controller';
import { IndividualService } from './individual.service';

@Module({
  imports: [JobsModule],
  controllers: [IndividualController],
  providers: [IndividualService],
})
export class IndividualModule {}
