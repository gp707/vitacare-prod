import { IsOptional, Matches } from 'class-validator';

/** Marks a salary cycle as paid. [paid_on] (YYYY-MM-DD) defaults to today (IST). */
export class MarkCyclePaidDto {
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  paid_on?: string;
}
