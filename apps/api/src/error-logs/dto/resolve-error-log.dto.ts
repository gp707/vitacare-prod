import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ResolveErrorLogDto {
  /** What was done, e.g. "Called, re-registered them". Optional. */
  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(1000, { message: 'GEN_001' })
  note?: string;
}
