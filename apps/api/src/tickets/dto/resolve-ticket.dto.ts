import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ResolveTicketDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  notes?: string;
}
