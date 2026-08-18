import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class RejectJobDto {
  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  reason!: string;
}
