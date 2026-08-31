import { ArrayMinSize, IsArray, IsString } from 'class-validator';

export class UpdateScopeOfWorkDto {
  // Validated as a non-empty array of non-empty strings in ScopeOfWorkService
  // — class-validator's `each: true` string check doesn't reject blank
  // strings, and this needs its own SCOPE_001 error code rather than the
  // generic GEN_001 the decorators below fall back to.
  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  companion_care!: string[];

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  bedside_care!: string[];

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(1, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  critical_care!: string[];
}
