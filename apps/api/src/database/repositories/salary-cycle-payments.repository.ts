import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { PaidCycleRow, SalaryUnit } from '../../common/salary-cycles';

/** Cycles the patient/family has marked as paid (migration 095). Each row is a
 *  frozen record of that cycle — later changes never rewrite it. */
@Injectable()
export class SalaryCyclePaymentsRepository {
  constructor(private readonly db: DatabaseService) {}

  async listByApplication(applicationId: string): Promise<PaidCycleRow[]> {
    const result = await this.db.query<PaidCycleRow>(
      `SELECT cycle_start::text, cycle_end::text, rate, rate_unit, leave_dates,
              worked_days, amount, paid_on::text
       FROM salary_cycle_payments WHERE application_id = $1 ORDER BY cycle_start`,
      [applicationId],
    );
    return result.rows;
  }

  /** Freezes a paid cycle. False when that cycle was already marked paid. */
  async insert(
    applicationId: string,
    row: {
      cycle_start: string;
      cycle_end: string;
      rate: number;
      rate_unit: SalaryUnit;
      leave_dates: string[];
      worked_days: number;
      amount: number;
      paid_on: string;
    },
    markedBy: string,
  ): Promise<boolean> {
    const result = await this.db.query(
      `INSERT INTO salary_cycle_payments
         (application_id, cycle_start, cycle_end, rate, rate_unit, leave_dates, worked_days, amount, paid_on, marked_by)
       VALUES ($1, $2::date, $3::date, $4, $5, $6::jsonb, $7, $8, $9::date, $10)
       ON CONFLICT (application_id, cycle_start) DO NOTHING
       RETURNING id`,
      [
        applicationId,
        row.cycle_start,
        row.cycle_end,
        row.rate,
        row.rate_unit,
        JSON.stringify(row.leave_dates),
        row.worked_days,
        row.amount,
        row.paid_on,
        markedBy,
      ],
    );
    return (result.rowCount ?? 0) > 0;
  }
}
