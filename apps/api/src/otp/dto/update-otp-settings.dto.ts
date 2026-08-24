import { IsBoolean } from 'class-validator';

export class UpdateOtpSettingsDto {
  @IsBoolean({ message: 'GEN_001' })
  enabled!: boolean;
}
