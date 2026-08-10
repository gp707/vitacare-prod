import { ArrayMinSize, IsArray, IsIn, IsInt, Max, Min } from 'class-validator';
import { Language, Validation } from '@vitacare/shared-constants';

// Full name and gender are intentionally NOT editable by the caregiver
// themselves — they're identity fields admins keep sole control over once
// set at registration. Everything else here can be self-edited; see
// update-phone.dto.ts and update-code.dto.ts for the identity-sensitive
// fields that live on their own endpoints (each with different
// review-trigger semantics).
export class UpdateBasicProfileDto {
  @IsInt({ message: 'PROFILE_004' })
  @Min(Validation.AGE_MIN, { message: 'PROFILE_004' })
  @Max(Validation.AGE_MAX, { message: 'PROFILE_004' })
  age!: number;

  @IsArray({ message: 'PROFILE_005' })
  @ArrayMinSize(1, { message: 'PROFILE_005' })
  @IsIn(Object.values(Language), { each: true, message: 'PROFILE_006' })
  languages!: Language[];
}
