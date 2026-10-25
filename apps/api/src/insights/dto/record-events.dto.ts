import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsDateString, IsIn, IsOptional, Matches, ValidateNested } from 'class-validator';

/** Hard cap per request — the app flushes small batches, and this endpoint
 *  accepts anonymous (pre-login) traffic, so it must never accept an
 *  unbounded write. */
export const MAX_EVENTS_PER_REQUEST = 25;

export class AppEventDto {
  @IsIn(['screen', 'tap'], { message: 'GEN_005' })
  kind!: 'screen' | 'tap';

  /** Which part of the app: 'auth', 'individual', 'organisation',
   *  'caregiver', ... — free-form so a new flow never needs a backend
   *  change, but strictly shaped so nothing sensitive can ride along. */
  @Matches(/^[a-z0-9_]{1,40}$/, { message: 'GEN_005' })
  flow!: string;

  /** Route name or screen identifier, e.g. '/org-home', 'login'. */
  @Matches(/^[A-Za-z0-9_/.:-]{1,60}$/, { message: 'GEN_005' })
  screen!: string;

  /** Button identifier, e.g. 'post_requirement'. Absent for screen views. */
  @IsOptional()
  @Matches(/^[a-z0-9_]{1,60}$/, { message: 'GEN_005' })
  action?: string;

  /** When it happened on the device (ISO 8601); the server clamps it. */
  @IsOptional()
  @IsDateString({}, { message: 'GEN_005' })
  occurred_at?: string;
}

export class RecordEventsDto {
  @IsArray({ message: 'GEN_005' })
  @ArrayMinSize(1, { message: 'GEN_005' })
  @ArrayMaxSize(MAX_EVENTS_PER_REQUEST, { message: 'GEN_005' })
  @ValidateNested({ each: true })
  @Type(() => AppEventDto)
  events!: AppEventDto[];
}
