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
    expect(find.text('Start date: 20 Nov 2026'), findsOneWidget);
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
      expect(find.text('₹14,000 for 2 weeks'), findsOneWidget);
      expect(find.text('₹1,000/day × 14 days'), findsOneWidget);
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
}
