import { IsNumber, Min } from 'class-validator';

export class UpdateSalaryDto {
  @IsNumber({}, { message: 'PROFILE_024' })
  @Min(0, { message: 'PROFILE_024' })
  salary!: number;
}
