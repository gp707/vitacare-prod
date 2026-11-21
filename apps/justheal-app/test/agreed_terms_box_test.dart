import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/agreed_terms_box.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/job_detail_card.dart';

void main() {
  testWidgets('shows the salary in the job\'s unit and the start date in words', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AgreedTermsBox(salary: 800, perUnit: 'day', startDate: '2026-11-20')),
    ));
    expect(find.text('Agreed with the family'), findsOneWidget);
    expect(find.text('Salary: ₹800 per day'), findsOneWidget);
    expect(find.text('Start date: 20 Nov 2026'), findsOneWidget);
    // Just the two agreed facts: no leave, no next-salary box, no salary history any more.
    expect(find.byKey(const Key('leave-section')), findsNothing);
    expect(find.textContaining('Next salary'), findsNothing);
    expect(find.textContaining('Salary history'), findsNothing);
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

  group('the caregiver\'s activity log records every salary / start date change by the family', () {
    MyApplicationModel app(List<Map<String, dynamic>> history) => MyApplicationModel.fromJson({
          'status': 'accepted',
          'decided_by_admin': false,
          'accepted_at': '2026-11-01T10:00:00Z',
          'applied_at': '2026-10-30T10:00:00Z',
          'agreement_history': history,
        });

    Future<void> pump(WidgetTester tester, MyApplicationModel a) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApplicationTimeline(a)))));

    testWidgets('lists "entered" then each "changed", with the amount and start date', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      expect(find.textContaining('Salary and start date entered by the family'), findsOneWidget);
      expect(find.textContaining('Salary and start date changed by the family'), findsOneWidget);
      expect(find.textContaining('₹30,000 per month, starts 1 Nov 2026'), findsOneWidget);
      expect(find.textContaining('₹1,200 per day, starts 26 Nov 2026'), findsOneWidget);
    });

    testWidgets('with no history, no salary line (the rest of the log is unchanged)', (tester) async {
      await pump(tester, app(const []));
      expect(find.textContaining('Salary and start date'), findsNothing);
      expect(find.textContaining('Accepted by employer'), findsOneWidget);
    });
  });
}
