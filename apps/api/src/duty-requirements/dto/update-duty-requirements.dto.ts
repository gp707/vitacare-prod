import { ArrayMinSize, IsArray, IsString } from 'class-validator';

export class UpdateDutyRequirementsDto {
  // Validated as a non-empty array of non-empty strings in
  // DutyRequirementsService — class-validator's `each: true` string check
  // doesn't reject blank strings, and this needs its own DUTY_001 error
  // code rather than the generic GEN_001 the decorators below fall back to.
  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  live_in!: string[];

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  day_duty!: string[];

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  night_duty!: string[];
}
