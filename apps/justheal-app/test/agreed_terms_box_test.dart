import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/agreed_terms_box.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/salary_due_banner.dart';

void main() {
  testWidgets('shows the salary in the job\'s unit and the start date in words', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AgreedTermsBox(salary: 800, perUnit: 'day', startDate: '2026-11-20')),
    ));
    expect(find.text('Agreed with the family'), findsOneWidget);
    expect(find.text('Salary: ₹800 per day'), findsOneWidget);
    expect(find.text('Cycle start date: 20 Nov 2026'), findsOneWidget);
  });

  test('formatDate falls back to the raw text for something that is not a date', () {
    expect(AgreedTermsBox.formatDate('soon'), 'soon');
  });

  group('the agreement comes through the shared models', () {
    test("MyApplicationModel reads the caregiver's own agreed salary and start date", () {
      final model = MyApplicationModel.fromJson({
        'status': 'accepted',
        'decided_by_admin': true,
        'agreed_salary': 800,
        'agreed_salary_unit': 'daily',
        'agreed_start_date': '2026-11-20',
      });
      expect(model.agreedSalary, 800);
      expect(model.agreedSalaryUnit, 'daily');
      expect(model.agreedStartDate, '2026-11-20');
    });

    test('both are null until the patient fills them in (and for older API responses)', () {
      final model = MyApplicationModel.fromJson({'status': 'accepted', 'decided_by_admin': true});
      expect(model.agreedSalary, isNull);
      expect(model.agreedSalaryUnit, isNull);
      expect(model.agreedStartDate, isNull);
    });
  });
  group('SalaryDueBanner (caregiver)', () {
    SalaryDue due(int rate, String unit, String start, DateTime today) =>
        nextSalaryDue(salary: rate, unit: unit, startDate: start, today: today)!;
    final today = DateTime(2026, 11, 16);

    testWidgets('shows the due date, days left, the 2-week amount and the rate working', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SalaryDueBanner(
            entries: [SalaryDueEntry(label: 'PAT-JOB-548', due: due(1000, 'daily', '2026-11-20', today))],
            caption: 'Salary is paid directly by the family, every 2 weeks.',
          ),
        ),
      ));
      expect(find.text('Salary due Fri 4 Dec 2026 (in 18 days)'), findsOneWidget);
      expect(find.text('₹14,000'), findsOneWidget);
      expect(find.text('for 2 weeks'), findsOneWidget);
      expect(find.text('₹1,000/day × 14 days = ₹14,000'), findsOneWidget);
      expect(find.text('Salary is paid directly by the family, every 2 weeks.'), findsOneWidget);
    });

    testWidgets('lists the soonest first, labels each job, and caps at three with "+ n more"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SalaryDueBanner(
              entries: [
                SalaryDueEntry(label: 'JOB-D', due: due(1000, 'daily', '2026-12-10', today)),
                SalaryDueEntry(label: 'JOB-A', due: due(1000, 'daily', '2026-11-20', today)),
                SalaryDueEntry(label: 'JOB-C', due: due(1000, 'daily', '2026-12-01', today)),
                SalaryDueEntry(label: 'JOB-B', due: due(1000, 'daily', '2026-11-25', today)),
              ],
              caption: 'caption',
            ),
          ),
        ),
      ));
      final a = tester.getTopLeft(find.text('JOB-A')).dy;
      final b = tester.getTopLeft(find.text('JOB-B')).dy;
      final c = tester.getTopLeft(find.text('JOB-C')).dy;
      expect(a, lessThan(b));
      expect(b, lessThan(c));
      expect(find.text('JOB-D'), findsNothing);
      expect(find.text('+ 1 more'), findsOneWidget);
    });

    testWidgets('renders nothing without entries', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SalaryDueBanner(entries: [], caption: 'x')),
      ));
      expect(find.byKey(const Key('salary-due-banner')), findsNothing);
    });

    testWidgets('says "today" on the due day', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SalaryDueBanner(
            entries: [SalaryDueEntry(label: 'X', due: due(1000, 'daily', '2026-11-20', DateTime(2026, 12, 4)))],
            caption: 'c',
          ),
        ),
      ));
      expect(find.text('Salary due Fri 4 Dec 2026 (today)'), findsOneWidget);
    });
  });

  group('what the caregiver sees about leave', () {
    Widget box({List<String> leave = const []}) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgreedTermsBox(
                salary: 800,
                perUnit: 'day',
                startDate: '2026-11-20',
                leaveDates: leave,
              ),
            ),
          ),
        );

    testWidgets('no leave section until the family marks something', (tester) async {
      await tester.pumpWidget(box());
      expect(find.byKey(const Key('leave-section')), findsNothing);
    });

    testWidgets('each leave day is listed as an orange chip, with a note that leave is not paid', (tester) async {
      await tester.pumpWidget(box(leave: ['2026-11-24', '2026-11-25']));
      expect(find.byKey(const Key('leave-section')), findsOneWidget);
      expect(find.text('On leave (not paid)'), findsOneWidget);
      expect(find.text('Tue 24 Nov'), findsOneWidget);
      expect(find.text('Wed 25 Nov'), findsOneWidget);
    });

  });

  group('SalaryDueBanner with leave (caregiver)', () {
    final today = DateTime(2026, 11, 20);

    testWidgets('shows the reduced amount, the days worked, and names every leave day', (tester) async {
      final due = nextSalaryDue(
        salary: 1000,
        unit: 'daily',
        startDate: '2026-11-18',
        today: today,
        leaveDates: ['2026-11-24', '2026-11-25'],
      )!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SalaryDueBanner(entries: [SalaryDueEntry(label: 'PAT-JOB-548', due: due)], caption: 'c')),
      ));
      expect(find.text('₹12,000'), findsOneWidget);
      expect(find.text('for 12 working days'), findsOneWidget);
      expect(find.text('₹1,000/day × 12 days = ₹12,000'), findsOneWidget);
      expect(find.text('On leave (2 of 14 days): Tue 24 Nov, Wed 25 Nov'), findsOneWidget);
    });

    testWidgets('a long run of leave is shortened to six days plus a count', (tester) async {
      final due = nextSalaryDue(
        salary: 1000,
        unit: 'daily',
        startDate: '2026-11-18',
        today: today,
        leaveDates: [for (var d = 19; d <= 27; d++) '2026-11-$d'],
      )!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SalaryDueBanner(entries: [SalaryDueEntry(label: 'X', due: due)], caption: 'c'))),
      ));
      expect(find.textContaining('+3 more'), findsOneWidget);
    });
  });
}
