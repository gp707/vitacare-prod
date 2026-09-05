import { IsIn, Matches } from 'class-validator';
import { AppPlatform, LoginApp } from '@vitacare/shared-constants';

export class VersionCheckQueryDto {
  // Which app is asking — NurseJobs and NurseNow have independent
  // min_version rows per platform (see migration 068), same "which app am
  // I" bucket LoginApp already models for POST /auth/login/code.
  @IsIn(Object.values(LoginApp), { message: 'GEN_001' })
  app!: LoginApp;

  @IsIn(Object.values(AppPlatform), { message: 'GEN_001' })
  platform!: AppPlatform;

  // e.g. "1.0.0" or "1.0" — matches how PackageInfo.version comes back
  // across platforms without being stricter than necessary.
  @Matches(/^\d+(\.\d+){0,2}$/, { message: 'GEN_001' })
  version!: string;
}
