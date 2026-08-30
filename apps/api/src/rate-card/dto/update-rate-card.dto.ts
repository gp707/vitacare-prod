import { ArrayMaxSize, ArrayMinSize, IsArray, IsNotEmpty, IsString } from 'class-validator';

export class UpdateRateCardDto {
  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  title!: string;

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(3, { message: 'GEN_001' })
  @ArrayMaxSize(3, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  column_labels!: string[];

  @IsArray({ message: 'GEN_001' })
  @ArrayMinSize(3, { message: 'GEN_001' })
  @ArrayMaxSize(3, { message: 'GEN_001' })
  @IsString({ each: true, message: 'GEN_001' })
  row_labels!: string[];

  // Validated as a 3x3 grid of strings in RateCardService — class-validator
  // has no clean built-in decorator for a nested string[][] shape, and this
  // needs its own RATE_001 error code rather than the generic GEN_001 the
  // decorators above fall back to.
  @IsArray({ message: 'GEN_001' })
  cells!: string[][];
}
