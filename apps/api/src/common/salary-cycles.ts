/**
 * Salary is paid every 14 days (a "cycle") counted from the agreed cycle start
 * date. This is the one place the cycles and their amounts are worked out on the
 * server, so the patient's and the caregiver's apps always show the same figures.
 * (The apps' own "next salary due" banner uses the equivalent maths in
 * packages/vitacare_shared/lib/models/salary_due.dart.)
 *
 * A cycle covers 14 days: cycle_start .. cycle_end inclusive; it is due the day
 * after it ends. A per-day rate is paid for the days worked, a per-month rate for
 * worked ÷ 30 of the month. Leave days inside the cycle are not paid.
 */
export const SALARY_PERIOD_DAYS = 14;
export const SALARY_MONTH_DAYS = 30;

export type SalaryUnit = 'daily' | 'monthly';
export type SalaryCycleStatus = 'paid' | 'due' | 'current';

export interface SalaryCycle {
  cycle_start: string;
  cycle_end: string;
  /** The rate that applies to (or applied to, once paid) this cycle. */
  rate: number;
  rate_unit: SalaryUnit;
  leave_dates: string[];
  worked_days: number;
  amount: number;
  /** paid = marked paid; due = ended, not yet paid; current = still running. */
  status: SalaryCycleStatus;
  /** The day it was paid (YYYY-MM-DD), only when status is paid. */
  paid_on: string | null;
}

/** One frozen, already-paid cycle (a salary_cycle_payments row). */
export interface PaidCycleRow {
  cycle_start: string;
  cycle_end: string;
  rate: number;
  rate_unit: SalaryUnit;
  leave_dates: string[];
  worked_days: number;
  amount: number;
  paid_on: string;
}

const DAY_MS = 24 * 3600 * 1000;

const toDay = (iso: string): number => Date.parse(`${iso}T00:00:00Z`);
const fromDay = (ms: number): string => new Date(ms).toISOString().slice(0, 10);

export function addDays(iso: string, days: number): string {
  return fromDay(toDay(iso) + days * DAY_MS);
}

/** Rupees for [workedDays] worked days at [rate]. */
export function salaryForDays(rate: number, unit: SalaryUnit, workedDays: number): number {
  return unit === 'daily' ? rate * workedDays : Math.round((rate * workedDays) / SALARY_MONTH_DAYS);
}

/** Works out one cycle from its start date and the current agreement. */
export function buildCycle(
  cycleStart: string,
  rate: number,
  unit: SalaryUnit,
  leaveDates: string[],
  today: string,
): SalaryCycle {
  const cycleEnd = addDays(cycleStart, SALARY_PERIOD_DAYS - 1);
  const leave = [...new Set(leaveDates)].filter((d) => d >= cycleStart && d <= cycleEnd).sort();
  const worked = SALARY_PERIOD_DAYS - leave.length;
  return {
    cycle_start: cycleStart,
    cycle_end: cycleEnd,
    rate,
    rate_unit: unit,
    leave_dates: leave,
    worked_days: worked,
    amount: salaryForDays(rate, unit, worked),
    status: cycleEnd < today ? 'due' : 'current',
    paid_on: null,
  };
}

/**
 * Every cycle of one caregiver on one job, newest first: the paid ones exactly as
 * they were frozen, plus (only while [agreement] is given, i.e. the caregiver is
 * still on the job) every cycle from the agreed start date up to today that has not
 * been paid, worked out from the current rate and leave days. A cycle that overlaps
 * a paid one is skipped, so moving the cycle start date never duplicates or
 * rewrites history.
 */
export function listSalaryCycles(params: {
  paid: PaidCycleRow[];
  agreement: { startDate: string; rate: number; unit: SalaryUnit; leaveDates: string[] } | null;
  today: string;
}): SalaryCycle[] {
  const { paid, agreement, today } = params;
  const cycles: SalaryCycle[] = paid.map((row) => ({
    cycle_start: row.cycle_start,
    cycle_end: row.cycle_end,
    rate: row.rate,
    rate_unit: row.rate_unit,
    leave_dates: [...row.leave_dates].sort(),
    worked_days: row.worked_days,
    amount: row.amount,
    status: 'paid',
    paid_on: row.paid_on,
  }));

  if (agreement && agreement.rate > 0) {
    const overlapsPaid = (start: string, end: string) =>
      paid.some((p) => start <= p.cycle_end && end >= p.cycle_start);
    for (let start = agreement.startDate; start <= today; start = addDays(start, SALARY_PERIOD_DAYS)) {
      const end = addDays(start, SALARY_PERIOD_DAYS - 1);
      if (overlapsPaid(start, end)) continue;
      cycles.push(buildCycle(start, agreement.rate, agreement.unit, agreement.leaveDates, today));
    }
  }
  return cycles.sort((a, b) => (a.cycle_start < b.cycle_start ? 1 : a.cycle_start > b.cycle_start ? -1 : 0));
}
