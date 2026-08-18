import { IsIn } from 'class-validator';

export class UnblockIndividualDto {
  @IsIn(['job_posting', 'full'], { message: 'GEN_001' })
  level!: 'job_posting' | 'full';
}
