import { IsIn, Matches } from 'class-validator';
import { AppPlatform } from '@vitacare/shared-constants';

export class VersionCheckQueryDto {
  @IsIn(Object.values(AppPlatform), { message: 'GEN_001' })
  platform!: AppPlatform;

  // e.g. "1.0.0" or "1.0" — matches how PackageInfo.version comes back
  // across platforms without being stricter than necessary.
  @Matches(/^\d+(\.\d+){0,2}$/, { message: 'GEN_001' })
  version!: string;
}
