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
import { CareDuration, City, DutyType, FrequencyOfCare, Gender, Language, Religion } from '@vitacare/shared-constants';
import { CareReceiverDto } from '../../jobs/dto/create-job.dto';

/** Same shape as CreateIndividualRequirementDto — every field, including
 *  frequency_of_care/salary_amount, is always required and always
 *  editable now (both are derived/re-derived client-side on every save,
 *  same as at creation; there's no more "only after admin approval" gate). */
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

  /** Always editable, unlike frequency_of_care/salary_amount below — see
   *  CreateIndividualRequirementDto. */
  @IsIn(Object.values(CareDuration), { message: 'GEN_001' })
  care_duration!: CareDuration;

  /** Empty array means "No Preference" — see CreateIndividualRequirementDto. */
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(Language), { each: true, message: 'GEN_001' })
  languages!: Language[];

  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: Gender;

  @IsOptional()
  @IsIn([Religion.HINDU, Religion.MUSLIM, Religion.CHRISTIAN], { message: 'GEN_001' })
  preferred_religion?: Religion;

  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care!: FrequencyOfCare;

  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  salary_amount!: string;
}
