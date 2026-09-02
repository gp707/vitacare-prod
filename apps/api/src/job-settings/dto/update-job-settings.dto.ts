import { IsInt, Min } from 'class-validator';

export class UpdateJobSettingsDto {
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  apply_by_window_days!: number;
}
