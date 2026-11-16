import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day, 15, 30); // time of day must not matter

void main() {
  leaveTests();
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
    test('short day label with weekday', () {
      expect(formatDayMonth('2026-11-25'), 'Wed 25 Nov');
      expect(formatDayMonth('soon'), 'soon');
    });
    test('long date without weekday, and a fallback for unreadable text', () {
      expect(formatLongDate('2026-11-18'), '18 Nov 2026');
      expect(formatLongDate('soon'), 'soon');
    });
    test('due in words', () {
      expect(dueInWords(0), 'today');
      expect(dueInWords(1), 'tomorrow');
      expect(dueInWords(12), 'in 12 days');
    });
  });
}

void leaveTests() {
  DateTime day(int y, int m, int d) => DateTime(y, m, d, 12);

  group('nextSalaryDue with leave days and pauses', () {
    // Start 2026-11-18: first period covers 18 Nov .. 1 Dec (14 days), due 2 Dec.
    SalaryDue due({List<String> leave = const [], List<PausePeriod> pauses = const [], String unit = 'daily', int rate = 1000, DateTime? today}) =>
        nextSalaryDue(
          salary: rate,
          unit: unit,
          startDate: '2026-11-18',
          today: today ?? day(2026, 11, 20),
          leaveDates: leave,
          pauses: pauses,
        )!;

    test('with no leave, nothing changes', () {
      final d = due();
      expect(d.workedDays, 14);
      expect(d.leaveDays, isEmpty);
      expect(d.amount, 14000);
      expect(d.isPaused, isFalse);
    });

    test('a daily rate is paid only for the days worked', () {
      final d = due(leave: ['2026-11-24', '2026-11-25', '2026-11-26']);
      expect(d.workedDays, 11);
      expect(d.leaveDays.length, 3);
      expect(d.amount, 11000);
    });

    test('a monthly rate is paid as worked days / 30 of the month', () {
      final d = due(unit: 'monthly', rate: 30000, leave: ['2026-11-24', '2026-11-25']);
      expect(d.workedDays, 12);
      expect(d.amount, 12000); // 30000 * 12 / 30
    });

    test('leave days outside this 14-day period do not count', () {
      final d = due(leave: ['2026-11-10', '2026-12-05']);
      expect(d.workedDays, 14);
      expect(d.amount, 14000);
    });

    test('leave days listed in the period come back sorted, each once', () {
      final d = due(leave: ['2026-11-26', '2026-11-24', '2026-11-24']);
      expect(d.leaveDays.map((x) => x.day).toList(), [24, 26]);
    });

    test('an open pause makes every day from then to the end of the period leave', () {
      // Paused on 25 Nov: 18..24 Nov worked = 7 days, 25 Nov..1 Dec = 7 days leave.
      final d = due(pauses: [const PausePeriod(from: '2026-11-25')]);
      expect(d.isPaused, isTrue);
      expect(d.pausedFrom, DateTime.utc(2026, 11, 25));
      expect(d.workedDays, 7);
      expect(d.amount, 7000);
    });

    test('a resumed pause only covers the days it was on, the resume day is a working day', () {
      // Paused 25 Nov, resumed 28 Nov: 25, 26, 27 Nov are leave.
      final d = due(pauses: [const PausePeriod(from: '2026-11-25', to: '2026-11-28')]);
      expect(d.isPaused, isFalse);
      expect(d.leaveDays.map((x) => x.day).toList(), [25, 26, 27]);
      expect(d.workedDays, 11);
    });

    test('a day that is both marked as leave and inside a pause counts once', () {
      final d = due(leave: ['2026-11-26'], pauses: [const PausePeriod(from: '2026-11-25', to: '2026-11-28')]);
      expect(d.leaveDays.length, 3);
      expect(d.workedDays, 11);
    });

    test('a pause that started in an earlier period and is still open leaves nothing payable', () {
      final d = nextSalaryDue(
        salary: 1000,
        unit: 'daily',
        startDate: '2026-11-18',
        today: day(2026, 12, 10),
        pauses: [const PausePeriod(from: '2026-11-25')],
      )!;
      // This period is 2 Dec..15 Dec, entirely inside the open pause.
      expect(d.workedDays, 0);
      expect(d.amount, 0);
      expect(d.isPaused, isTrue);
    });

    test('a pause that starts after this period does not affect it', () {
      final d = due(pauses: [const PausePeriod(from: '2026-12-10')]);
      expect(d.workedDays, 14);
      expect(d.isPaused, isTrue);
    });
  });

  group('helpers', () {
    test('isoDatesBetween lists every day inclusive', () {
      expect(isoDatesBetween(DateTime(2026, 11, 24), DateTime(2026, 11, 26)), ['2026-11-24', '2026-11-25', '2026-11-26']);
      expect(isoDatesBetween(DateTime(2026, 11, 24), DateTime(2026, 11, 24)), ['2026-11-24']);
      expect(isoDatesBetween(DateTime(2026, 11, 26), DateTime(2026, 11, 24)), isEmpty);
    });
    test('isoDatesBetween crosses a month end', () {
      expect(isoDatesBetween(DateTime(2026, 11, 29), DateTime(2026, 12, 2)).length, 4);
    });
    test('PausePeriod.covers treats the resume day as a working day', () {
      const p = PausePeriod(from: '2026-11-25', to: '2026-11-28');
      expect(p.covers('2026-11-24'), isFalse);
      expect(p.covers('2026-11-25'), isTrue);
      expect(p.covers('2026-11-27'), isTrue);
      expect(p.covers('2026-11-28'), isFalse);
    });
    test('parsers are tolerant of missing data', () {
      expect(parseLeaveDates(null), isEmpty);
      expect(parseLeaveDates(['2026-11-26', '2026-11-24']), ['2026-11-24', '2026-11-26']);
      expect(parsePauses(null), isEmpty);
      expect(parsePauses([{'from': '2026-11-25', 'to': null}]).single.isOpen, isTrue);
    });
  });
}
