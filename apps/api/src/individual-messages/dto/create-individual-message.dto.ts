import { IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';
import { MessageEvent, MessageIcon } from '@vitacare/shared-constants';

const MESSAGE_EVENTS = Object.values(MessageEvent);
const MESSAGE_ICONS = Object.values(MessageIcon);

export class CreateIndividualMessageDto {
  @IsIn(MESSAGE_EVENTS, { message: 'GEN_001' })
  event!: string;

  @IsIn(MESSAGE_ICONS, { message: 'GEN_001' })
  icon!: string;

  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(1000, { message: 'GEN_001' })
  message!: string;

  @IsInt({ message: 'GEN_001' })
  display_order!: number;

  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  enabled?: boolean;
}
