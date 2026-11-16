import { Transform } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/** One overall feedback: 1-5 stars and an optional short comment. */
export class SubmitFeedbackDto {
  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MaxLength(Validation.FEEDBACK_COMMENT_MAX_LENGTH)
  comment?: string;
}
