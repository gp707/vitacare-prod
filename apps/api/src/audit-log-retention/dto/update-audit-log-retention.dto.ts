import { IsInt, Max, Min } from 'class-validator';

export class UpdateAuditLogRetentionDto {
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(3650, { message: 'GEN_001' })
  retention_days!: number;
}
