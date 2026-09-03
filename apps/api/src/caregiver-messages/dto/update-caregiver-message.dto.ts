import { IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';
import { CaregiverMessageEvent, MessageIcon } from '@vitacare/shared-constants';

const CAREGIVER_MESSAGE_EVENTS = Object.values(CaregiverMessageEvent);
const MESSAGE_ICONS = Object.values(MessageIcon);

export class UpdateCaregiverMessageDto {
  @IsOptional()
  @IsIn(CAREGIVER_MESSAGE_EVENTS, { message: 'GEN_001' })
  event?: string;

  @IsOptional()
  @IsIn(MESSAGE_ICONS, { message: 'GEN_001' })
  icon?: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(1000, { message: 'GEN_001' })
  message?: string;

  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  display_order?: number;

  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  enabled?: boolean;
}
