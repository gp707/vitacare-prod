import { Module } from '@nestjs/common';
import { UploadModule } from '../upload/upload.module';
import { CaregiverController } from './caregiver.controller';
import { CaregiverService } from './caregiver.service';

@Module({
  imports: [UploadModule],
  controllers: [CaregiverController],
  providers: [CaregiverService],
  exports: [CaregiverService],
})
export class CaregiverModule {}
