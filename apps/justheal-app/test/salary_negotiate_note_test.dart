import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/job_detail_card.dart';

void main() {
  testWidgets('tapping a job salary says it is a range to negotiate directly with the family', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SalaryBadge(amount: '26,000 - 30,000', frequencyOfCare: 'monthly')),
    ));
    await tester.tap(find.byType(SalaryBadge));
    await tester.pumpAndSettle();
    expect(find.text('This is a range, you can negotiate directly with the family.'), findsOneWidget);
  });

  for (final entry in {
    'the hospital': 'hospital',
    'the clinic': 'clinic',
    'the rehab': 'rehab',
    'the agency': 'agency',
  }.entries) {
    testWidgets('an organisation salary range names ${entry.key}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SalaryRangeLine(label: '₹4,500 – ₹5,000 per month', negotiateWith: entry.key)),
      ));
      await tester.tap(find.byKey(const Key('org-salary-range-tap')));
      await tester.pumpAndSettle();
      expect(find.text('This is a range, you can negotiate directly with ${entry.key}.'), findsOneWidget);
    });
  }
}
