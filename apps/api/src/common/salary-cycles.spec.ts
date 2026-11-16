import { addDays, listSalaryCycles, PaidCycleRow, salaryForDays } from './salary-cycles';

const agreement = (over: Partial<{ startDate: string; rate: number; unit: 'daily' | 'monthly'; leaveDates: string[] }> = {}) => ({
  startDate: '2026-11-18',
  rate: 1000,
  unit: 'daily' as const,
  leaveDates: [] as string[],
  ...over,
});

const paidRow = (over: Partial<PaidCycleRow> = {}): PaidCycleRow => ({
  cycle_start: '2026-11-18',
  cycle_end: '2026-12-01',
  rate: 900,
  rate_unit: 'daily',
  leave_dates: ['2026-11-20'],
  worked_days: 13,
  amount: 11700,
  paid_on: '2026-12-02',
  ...over,
});

describe('salary cycles', () => {
  it('adds days across month ends', () => {
    expect(addDays('2026-11-18', 13)).toBe('2026-12-01');
    expect(addDays('2026-12-30', 3)).toBe('2027-01-02');
  });

  it('works out a day rate and a 30-day-month rate', () => {
    expect(salaryForDays(1000, 'daily', 11)).toBe(11000);
    expect(salaryForDays(30000, 'monthly', 12)).toBe(12000);
  });

  it('shows only the running cycle while the first 14 days are not over', () => {
    const cycles = listSalaryCycles({ paid: [], agreement: agreement(), today: '2026-11-25' });
    expect(cycles).toHaveLength(1);
    expect(cycles[0]).toMatchObject({ cycle_start: '2026-11-18', cycle_end: '2026-12-01', status: 'current', amount: 14000, worked_days: 14 });
  });

  it('a finished, unpaid cycle is due, and the next one is current — newest first', () => {
    const cycles = listSalaryCycles({ paid: [], agreement: agreement(), today: '2026-12-02' });
    expect(cycles.map((c) => [c.cycle_start, c.status])).toEqual([
      ['2026-12-02', 'current'],
      ['2026-11-18', 'due'],
    ]);
  });

  it('the last day of a cycle is still current, the next day it is due', () => {
    expect(listSalaryCycles({ paid: [], agreement: agreement(), today: '2026-12-01' })[0].status).toBe('current');
    expect(listSalaryCycles({ paid: [], agreement: agreement(), today: '2026-12-02' }).find((c) => c.cycle_start === '2026-11-18')?.status).toBe('due');
  });

  it('takes the leave days inside each cycle, and only those', () => {
    const cycles = listSalaryCycles({
      paid: [],
      agreement: agreement({ leaveDates: ['2026-11-24', '2026-11-25', '2026-12-05'] }),
      today: '2026-12-10',
    });
    const first = cycles.find((c) => c.cycle_start === '2026-11-18')!;
    const second = cycles.find((c) => c.cycle_start === '2026-12-02')!;
    expect(first.leave_dates).toEqual(['2026-11-24', '2026-11-25']);
    expect(first.worked_days).toBe(12);
    expect(first.amount).toBe(12000);
    expect(second.leave_dates).toEqual(['2026-12-05']);
    expect(second.amount).toBe(13000);
  });

  it('a paid cycle keeps its own frozen rate and leave, whatever the agreement says now', () => {
    const cycles = listSalaryCycles({
      paid: [paidRow()],
      agreement: agreement({ rate: 1500, leaveDates: [] }),
      today: '2026-12-03',
    });
    const paid = cycles.find((c) => c.cycle_start === '2026-11-18')!;
    expect(paid).toMatchObject({ status: 'paid', rate: 900, amount: 11700, paid_on: '2026-12-02', leave_dates: ['2026-11-20'] });
    // the new cycle uses the new rate
    expect(cycles[0]).toMatchObject({ cycle_start: '2026-12-02', status: 'current', rate: 1500, amount: 21000 });
  });

  it('a paid cycle is never listed twice', () => {
    const cycles = listSalaryCycles({ paid: [paidRow()], agreement: agreement(), today: '2026-12-03' });
    expect(cycles.filter((c) => c.cycle_start === '2026-11-18')).toHaveLength(1);
  });

  it('moving the cycle start date never overlaps or rewrites a paid cycle', () => {
    // 18 Nov..1 Dec was paid; the family moves the start to 5 Dec.
    const cycles = listSalaryCycles({ paid: [paidRow()], agreement: agreement({ startDate: '2026-12-05' }), today: '2026-12-10' });
    expect(cycles.map((c) => [c.cycle_start, c.status])).toEqual([
      ['2026-12-05', 'current'],
      ['2026-11-18', 'paid'],
    ]);
    // a start date that would cut into the paid cycle is skipped, not doubled
    const overlapping = listSalaryCycles({ paid: [paidRow()], agreement: agreement({ startDate: '2026-11-25' }), today: '2026-12-10' });
    expect(overlapping.filter((c) => c.status !== 'paid').every((c) => c.cycle_start > '2026-12-01' || c.cycle_end < '2026-11-18')).toBe(true);
  });

  it('with no agreement (rejected or closed) only the paid history remains', () => {
    const cycles = listSalaryCycles({ paid: [paidRow()], agreement: null, today: '2027-02-01' });
    expect(cycles).toHaveLength(1);
    expect(cycles[0].status).toBe('paid');
  });

  it('a start date in the future has no cycles yet', () => {
    expect(listSalaryCycles({ paid: [], agreement: agreement({ startDate: '2026-12-20' }), today: '2026-12-10' })).toEqual([]);
  });
});
