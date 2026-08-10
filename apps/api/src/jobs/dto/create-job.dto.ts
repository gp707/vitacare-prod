import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';
import { City, Gender, Language, Religion, ServiceMode, WorkType } from '@vitacare/shared-constants';

export class CreateJobDto {
  @IsIn(Object.values(WorkType), { message: 'GEN_001' })
  work_type!: WorkType;

  @IsIn(Object.values(City), { message: 'GEN_001' })
  city!: City;

  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  @MaxLength(2000, { message: 'GEN_001' })
  description!: string;

  @IsIn(Object.values(ServiceMode), { message: 'GEN_001' })
  duty_timings!: ServiceMode;

  @IsIn(Object.values(Language), { message: 'GEN_001' })
  language!: Language;

  // Jobs table CHECK constraint only allows male/female (not 'other') —
  // matches SPEC.md's schema exactly.
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  gender_needed!: Gender;

  @IsIn(Object.values(Religion), { message: 'GEN_001' })
  religion!: Religion;
}
