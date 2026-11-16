import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/agreed_terms_box.dart';

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
}
