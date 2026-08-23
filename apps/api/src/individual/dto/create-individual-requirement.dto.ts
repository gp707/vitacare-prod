import {
  IsArray,
  IsDateString,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { City, DutyType, Gender, Language, Religion } from '@vitacare/shared-constants';
import { CareReceiverDto } from '../../jobs/dto/create-job.dto';

/** Same shape as CreateJobDto, minus frequency_of_care and salary_amount —
 *  those are admin-set during approval, not collected from the individual
 *  posting the requirement. */
export class CreateIndividualRequirementDto {
  @ValidateNested()
  @Type(() => CareReceiverDto)
  care_receiver!: CareReceiverDto;

  @IsIn(Object.values(City), { message: 'GEN_001' })
  city!: City;

  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  area!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000, { message: 'GEN_001' })
  description?: string;

  @IsIn(Object.values(DutyType), { message: 'GEN_001' })
  duty_type!: DutyType;

  @IsNotEmpty({ message: 'GEN_001' })
  @IsDateString({}, { message: 'GEN_001' })
  start_date!: string;

  /** Empty array means "No Preference" — a deliberate, non-mandatory
   *  choice (see nursenow-app's Post/Edit Requirement screens), not
   *  merely an unset field. Purely informational either way — never
   *  enforced as a caregiver-eligibility filter (see CLAUDE.md). */
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(Language), { each: true, message: 'GEN_001' })
  languages!: Language[];

  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: Gender;

  @IsOptional()
  @IsIn([Religion.HINDU, Religion.MUSLIM, Religion.CHRISTIAN], { message: 'GEN_001' })
  preferred_religion?: Religion;
}
