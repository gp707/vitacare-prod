import { ArrayMaxSize, ArrayMinSize, IsArray, Matches } from 'class-validator';

/** Days the patient/family marks as leave for the accepted caregiver. */
export class MarkLeaveDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(31)
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { each: true })
  dates!: string[];
}
