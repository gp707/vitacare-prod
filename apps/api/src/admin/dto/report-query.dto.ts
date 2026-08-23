import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Min } from 'class-validator';

/** "N days" threshold reports (e.g. stalled duty, activity) — admin types
 *  the number in on each run, see CLAUDE.md Admin Reports notes. */
export class ReportDaysQueryDto {
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(0, { message: 'GEN_005' })
  days!: number;
}

/** "more than x" count threshold reports. */
export class ReportMinJobsQueryDto {
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(0, { message: 'GEN_005' })
  min_jobs!: number;
}

/** Activity ranking reports — same "N days" window, plus a sort direction so
 *  one query answers both "most active" (desc) and "least active" (asc). */
export class ReportActivityQueryDto {
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(0, { message: 'GEN_005' })
  days!: number;

  @IsOptional()
  @IsIn(['asc', 'desc'], { message: 'GEN_005' })
  order: 'asc' | 'desc' = 'desc';
}
