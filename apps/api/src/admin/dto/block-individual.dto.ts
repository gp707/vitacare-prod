import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class BlockIndividualDto {
  // 'job_posting' blocks only new requirement postings — the existing
  // live requirement (if any) keeps working normally. 'full' is a login
  // lockout (reuses users.is_active).
  @IsIn(['job_posting', 'full'], { message: 'GEN_001' })
  level!: 'job_posting' | 'full';

  @IsNotEmpty({ message: 'GEN_001' })
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  reason!: string;
}
