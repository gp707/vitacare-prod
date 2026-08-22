import {
  ArrayNotEmpty,
  IsArray,
  IsDateString,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { City, DutyType, FrequencyOfCare, Gender, Language, Religion } from '@vitacare/shared-constants';
import { CareReceiverDto } from '../../jobs/dto/create-job.dto';

/** Same shape as CreateIndividualRequirementDto, plus optional
 *  frequency_of_care/salary_amount — unlike at creation, an edit MAY set
 *  these two, but only once the requirement has been approved by admin at
 *  least once (see IndividualService.editRequirement, JOB_013 otherwise).
 *  Every other field is always editable regardless of review state. */
export class UpdateIndividualRequirementDto {
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

  @IsArray({ message: 'GEN_001' })
  @ArrayNotEmpty({ message: 'GEN_001' })
  @IsIn(Object.values(Language), { each: true, message: 'GEN_001' })
  languages!: Language[];

  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: Gender;

  @IsOptional()
  @IsIn([Religion.HINDU, Religion.MUSLIM, Religion.CHRISTIAN], { message: 'GEN_001' })
  preferred_religion?: Religion;

  // Only settable once the requirement has been approved at least once
  // (JOB_013 otherwise) — omit entirely while still pending_review, same
  // as CreateIndividualRequirementDto never collects them.
  @IsOptional()
  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care?: FrequencyOfCare;

  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  salary_amount?: number;
}
