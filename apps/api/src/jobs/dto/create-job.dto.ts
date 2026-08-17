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
  FrequencyOfCare,
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

  // Not required — defaults to walks_independently when omitted (see
  // CARE_RECEIVER_DEFAULTS in jobs.service.ts).
  @IsOptional()
  @IsIn(Object.values(Mobility), { message: 'GEN_001' })
  mobility?: Mobility;

  // Not required — defaults to verbal ("Can Speak/Communicate") when omitted.
  @IsOptional()
  @IsIn(Object.values(Communication), { message: 'GEN_001' })
  communication?: Communication;

  // Not required — defaults to oral_independent when omitted.
  @IsOptional()
  @IsIn(Object.values(FeedingType), { message: 'GEN_001' })
  feeding_type?: FeedingType;

  // Not required — an empty/omitted selection defaults to
  // [medication_reminders] when omitted.
  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(MedicalAssistance), { each: true, message: 'GEN_001' })
  medical_assistance?: MedicalAssistance[];

  // Not required — defaults to false ("no health conditions") when omitted.
  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  has_medical_condition?: boolean;

  @ValidateIf((o: CareReceiverDto) => !!o.has_medical_condition)
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(MedicalCondition), { each: true, message: 'GEN_001' })
  medical_conditions?: MedicalCondition[];

  @IsOptional()
  @IsString()
  medical_info?: string;

  // Free-text detail for the 'other' MedicalCondition option — same
  // unconditional-optional treatment as medical_info; the admin-web form
  // only ever sends it when 'other' is actually selected, but the backend
  // doesn't need to enforce that itself.
  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  medical_condition_other?: string;

  // Not required — an empty/omitted selection defaults to [independent]
  // when omitted.
  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(ToiletAssistance), { each: true, message: 'GEN_001' })
  toilet_assistance?: ToiletAssistance[];

  // Free-text detail for the 'others' ToiletAssistance option.
  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  toilet_assistance_other?: string;

  // Not required — defaults to false ("monitoring not required") when omitted.
  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  requires_vital_monitoring?: boolean;

  @ValidateIf((o: CareReceiverDto) => !!o.requires_vital_monitoring)
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

  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  area!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000, { message: 'GEN_001' })
  description?: string;

  // Duty Type fully determines the shift's timing (see DUTY_TYPE_TIMES in
  // jobs.service.ts) — admins pick one of the 3 fixed shifts, they don't
  // enter start/end times separately.
  @IsIn(Object.values(DutyType), { message: 'GEN_001' })
  duty_type!: DutyType;

  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care!: FrequencyOfCare;

  @IsNotEmpty({ message: 'GEN_001' })
  @IsDateString({}, { message: 'GEN_001' })
  start_date!: string;

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  salary_monthly!: number;

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
