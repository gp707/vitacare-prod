import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import {
  City,
  Communication,
  DutyType,
  FeedingType,
  Gender,
  Language,
  MedicalAssistance,
  MedicalCondition,
  Mobility,
  Religion,
  ToiletAssistance,
  VitalMonitoringType,
} from '@vitacare/shared-constants';

export class CareReceiverDto {
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(120, { message: 'GEN_001' })
  age!: number;

  @IsIn(Object.values(Gender), { message: 'GEN_001' })
  gender!: Gender;

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(300, { message: 'GEN_001' })
  weight_kg!: number;

  @IsIn(Object.values(Mobility), { message: 'GEN_001' })
  mobility!: Mobility;

  @IsIn(Object.values(Communication), { message: 'GEN_001' })
  communication!: Communication;

  @IsIn(Object.values(FeedingType), { message: 'GEN_001' })
  feeding_type!: FeedingType;

  // Only meaningful when feeding_type involves tube feeding — validated as
  // present-if-relevant, not required, since the UI only shows this
  // question conditionally.
  @ValidateIf(
    (o: CareReceiverDto) =>
      o.feeding_type === FeedingType.TUBE_FEEDING || o.feeding_type === FeedingType.ORAL_AND_TUBE,
  )
  @IsBoolean({ message: 'GEN_001' })
  tube_feeding_needs_assistance?: boolean;

  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(MedicalAssistance), { each: true, message: 'GEN_001' })
  medical_assistance!: MedicalAssistance[];

  @IsBoolean({ message: 'GEN_001' })
  has_medical_condition!: boolean;

  @ValidateIf((o: CareReceiverDto) => o.has_medical_condition)
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(MedicalCondition), { each: true, message: 'GEN_001' })
  medical_conditions?: MedicalCondition[];

  @IsOptional()
  @IsString()
  medical_info?: string;

  @IsIn(Object.values(ToiletAssistance), { message: 'GEN_001' })
  toilet_assistance!: ToiletAssistance;

  @IsBoolean({ message: 'GEN_001' })
  requires_vital_monitoring!: boolean;

  @ValidateIf((o: CareReceiverDto) => o.requires_vital_monitoring)
  @IsArray({ message: 'GEN_001' })
  @ArrayNotEmpty({ message: 'GEN_001' })
  @IsIn(Object.values(VitalMonitoringType), { each: true, message: 'GEN_001' })
  vital_monitoring_types?: VitalMonitoringType[];
}

export class CreateJobDto {
  @ValidateNested()
  @Type(() => CareReceiverDto)
  care_receiver!: CareReceiverDto;

  @IsIn(Object.values(City), { message: 'GEN_001' })
  city!: City;

  @IsOptional()
  @IsString()
  area?: string;

  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  @MaxLength(2000, { message: 'GEN_001' })
  description!: string;

  // Duty Type fully determines the shift's timing (see DUTY_TYPE_TIMES in
  // jobs.service.ts) — admins pick one of the 3 fixed shifts, they don't
  // enter start/end times separately.
  @IsIn(Object.values(DutyType), { message: 'GEN_001' })
  duty_type!: DutyType;

  @IsOptional()
  @IsDateString({}, { message: 'GEN_001' })
  start_date?: string;

  @IsArray({ message: 'GEN_001' })
  @ArrayNotEmpty({ message: 'GEN_001' })
  @IsIn(Object.values(Language), { each: true, message: 'GEN_001' })
  languages!: Language[];

  // "No preference" is simply omitting the field — NOT a magic string.
  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: Gender;

  // "Others" is excluded here — it's a valid caregiver's own religion at
  // registration, but not offered as a job's stated preference.
  @IsOptional()
  @IsIn([Religion.HINDU, Religion.MUSLIM, Religion.CHRISTIAN], { message: 'GEN_001' })
  preferred_religion?: Religion;
}
