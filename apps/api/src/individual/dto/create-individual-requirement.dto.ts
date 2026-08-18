import {
  ArrayNotEmpty,
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
}
