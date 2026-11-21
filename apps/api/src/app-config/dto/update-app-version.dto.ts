import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from 'class-validator';
import { AppVersionAudienceCategory, AppVersionAudienceMode } from '@vitacare/shared-constants';

export class UpdateAppVersionDto {
  @Matches(/^\d+\.\d+\.\d+$/, { message: 'GEN_001' })
  min_version!: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  store_url?: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  update_message?: string;

  /** Who this minimum applies to. Omitted = leave the audience exactly as it is (an older admin-web
   *  that knows nothing about audiences must not reset it). 'all' = everyone; 'selected' = only the
   *  categories and/or accounts below (at least one of the two). */
  @IsOptional()
  @IsIn(Object.values(AppVersionAudienceMode), { message: 'GEN_001' })
  audience_mode?: AppVersionAudienceMode;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @ArrayMaxSize(20, { message: 'GEN_001' })
  @IsIn(Object.values(AppVersionAudienceCategory), { each: true, message: 'GEN_001' })
  audience_categories?: AppVersionAudienceCategory[];

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @ArrayMaxSize(500, { message: 'GEN_001' })
  @IsUUID('all', { each: true, message: 'GEN_001' })
  audience_user_ids?: string[];
}
