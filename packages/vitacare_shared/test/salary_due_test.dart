import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day, 15, 30); // time of day must not matter

void main() {
  group('salaryForPeriod', () {
    test('a daily rate is paid for 14 days', () {
      expect(salaryForPeriod(rate: 1000, unit: 'daily'), 14000);
    });
    test('a monthly rate is prorated as 14/30 of the month', () {
      expect(salaryForPeriod(rate: 30000, unit: 'monthly'), 14000);
      expect(salaryForPeriod(rate: 24000, unit: 'monthly'), 11200);
    });
    test('a monthly figure that does not divide evenly is rounded to the rupee', () {
      expect(salaryForPeriod(rate: 25000, unit: 'monthly'), 11667);
    });
  });

  group('nextSalaryDue', () {
    test('before the start date, the first payment is 14 days after the start', () {
      final due = nextSalaryDue(salary: 1000, unit: 'daily', startDate: '2026-11-20', today: d(2026, 11, 16))!;
      expect(due.dueDate, DateTime.utc(2026, 12, 4));
      expect(due.periodStart, DateTime.utc(2026, 11, 20));
      expect(due.daysLeft, 18);
      expect(due.amount, 14000);
    });

    test('on the start date the first payment is still 14 days away', () {
      final due = nextSalaryDue(salary: 1000, unit: 'daily', startDate: '2026-11-20', today: d(2026, 11, 20))!;
      expect(due.dueDate, DateTime.utc(2026, 12, 4));
      expect(due.daysLeft, 14);
    });

    test('on the due day itself it is due today', () {
      final due = nextSalaryDue(salary: 1000, unit: 'daily', startDate: '2026-11-20', today: d(2026, 12, 4))!;
      expect(due.dueDate, DateTime.utc(2026, 12, 4));
      expect(due.isDueToday, isTrue);
    });

    test('the day after a due date rolls to the next 14-day cycle', () {
      final due = nextSalaryDue(salary: 1000, unit: 'daily', startDate: '2026-11-20', today: d(2026, 12, 5))!;
      expect(due.dueDate, DateTime.utc(2026, 12, 18));
      expect(due.periodStart, DateTime.utc(2026, 12, 4));
      expect(due.daysLeft, 13);
    });

    test('many cycles later it keeps counting in 14-day steps from the start', () {
      final due = nextSalaryDue(salary: 30000, unit: 'monthly', startDate: '2026-11-20', today: d(2027, 3, 1))!;
      // 2026-11-20 + 14*n: ... 2027-02-26, 2027-03-12
      expect(due.dueDate, DateTime.utc(2027, 3, 12));
      expect(due.dueDate.difference(DateTime.utc(2026, 11, 20)).inDays % 14, 0);
      expect(due.amount, 14000);
    });

    test('crosses a daylight-saving boundary without drifting a day', () {
      final due = nextSalaryDue(salary: 1000, unit: 'daily', startDate: '2026-03-01', today: d(2026, 3, 20))!;
      expect(due.dueDate, DateTime.utc(2026, 3, 29));
    });

    test('returns null for an incomplete agreement', () {
      expect(nextSalaryDue(salary: null, unit: 'daily', startDate: '2026-11-20'), isNull);
      expect(nextSalaryDue(salary: 1000, unit: null, startDate: '2026-11-20'), isNull);
      expect(nextSalaryDue(salary: 1000, unit: 'weekly', startDate: '2026-11-20'), isNull);
      expect(nextSalaryDue(salary: 1000, unit: 'daily', startDate: null), isNull);
      expect(nextSalaryDue(salary: 1000, unit: 'daily', startDate: 'soon'), isNull);
      expect(nextSalaryDue(salary: 0, unit: 'daily', startDate: '2026-11-20'), isNull);
    });
  });

  group('formatting', () {
    test('Indian digit grouping', () {
      expect(formatRupees(0), '0');
      expect(formatRupees(900), '900');
      expect(formatRupees(14000), '14,000');
      expect(formatRupees(140000), '1,40,000');
      expect(formatRupees(1400000), '14,00,000');
    });
    test('due date with weekday', () {
      expect(formatDueDate(DateTime.utc(2026, 12, 4)), 'Fri 4 Dec 2026');
    });
    test('due in words', () {
      expect(dueInWords(0), 'today');
      expect(dueInWords(1), 'tomorrow');
      expect(dueInWords(12), 'in 12 days');
    });
  });
}
