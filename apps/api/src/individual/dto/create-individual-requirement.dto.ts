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

/** Same shape as CreateJobDto — including frequency_of_care/salary_amount,
 *  which used to be admin-set on approval but are now derived client-side
 *  from the individual's own care_duration/care_receiver selections (Rate
 *  Card suggestion for salary_amount) and submitted immediately at
 *  posting, same as nursenow-app's own Post/Edit Requirement screens. */
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

  /** How long the engagement is expected to last — also what
   *  frequency_of_care is derived from client-side (few_days/few_weeks ->
   *  daily, few_months/long_term -> monthly). */
  @IsIn(Object.values(CareDuration), { message: 'GEN_001' })
  care_duration!: CareDuration;

  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care!: FrequencyOfCare;

  // Free text, not a plain number — pre-filled client-side from the Rate
  // Card's suggested figure for the derived care tier/frequency, but
  // stays editable (e.g. a range with a note), same as CreateJobDto.
  @IsNotEmpty({ message: 'GEN_001' })
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  salary_amount!: string;

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
