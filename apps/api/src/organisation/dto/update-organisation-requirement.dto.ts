import {
  ArrayMinSize,
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { FrequencyOfCare, ScheduleRepeat, ScheduleType, TypeOfNurse } from '@vitacare/shared-constants';

/** Admin's approve-via-edit body — same shape as create plus the
 *  admin-set fields. schedule_type picks exactly one scheduling mode —
 *  a continuous date range (start_date/end_date) or a set of specific
 *  recurring days (specific_days) — deliberately organisation-only;
 *  regular jobs keep a single start_date. When schedule_type is
 *  specific_days, schedule_repeat further picks whether specific_days
 *  holds ISO weekdays (1-7, recurring weekly) or days-of-month (1-31,
 *  recurring monthly) — range-checked against schedule_repeat in the
 *  service layer (ORG_002), since the valid range depends on which repeat
 *  mode was chosen. Only the fields for the chosen mode are required
 *  (ORG_001 otherwise); the other mode's fields are ignored/nulled
 *  server-side regardless of what's sent. */
export class UpdateOrganisationRequirementDto {
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse!: string;

  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care!: string;

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  salary_amount!: number;

  @IsIn(Object.values(ScheduleType), { message: 'GEN_001' })
  schedule_type!: string;

  @ValidateIf((o) => o.schedule_type === ScheduleType.DATE_RANGE)
  @IsISO8601({ strict: true }, { message: 'ORG_001' })
  start_date?: string;

  @ValidateIf((o) => o.schedule_type === ScheduleType.DATE_RANGE)
  @IsISO8601({ strict: true }, { message: 'ORG_001' })
  end_date?: string;

  @ValidateIf((o) => o.schedule_type === ScheduleType.SPECIFIC_DAYS)
  @IsIn(Object.values(ScheduleRepeat), { message: 'ORG_001' })
  schedule_repeat?: string;

  @ValidateIf((o) => o.schedule_type === ScheduleType.SPECIFIC_DAYS)
  @IsArray({ message: 'ORG_001' })
  @ArrayNotEmpty({ message: 'ORG_001' })
  @ArrayMinSize(1, { message: 'ORG_001' })
  @IsInt({ each: true, message: 'ORG_001' })
  @Min(1, { each: true, message: 'ORG_001' })
  @Max(31, { each: true, message: 'ORG_001' })
  specific_days?: number[];

  @IsBoolean({ message: 'GEN_001' })
  accommodation_provided!: boolean;

  @IsBoolean({ message: 'GEN_001' })
  food_provided!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  special_skills?: string;
}
