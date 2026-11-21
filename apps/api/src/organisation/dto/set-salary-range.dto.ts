import { IsIn, IsInt, Max, Min } from 'class-validator';
import { FrequencyOfCare } from '@vitacare/shared-constants';

/** The salary range an organisation offers on a requirement, per day or per month. Edited at any time. */
export class SetSalaryRangeDto {
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1_000_000, { message: 'GEN_001' })
  salary_min!: number;

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1_000_000, { message: 'GEN_001' })
  salary_max!: number;

  @IsIn([FrequencyOfCare.DAILY, FrequencyOfCare.MONTHLY], { message: 'GEN_001' })
  salary_unit!: typeof FrequencyOfCare.DAILY | typeof FrequencyOfCare.MONTHLY;
}
