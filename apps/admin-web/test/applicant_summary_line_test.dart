import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/shared/widgets/applicant_summary_line.dart';

ApplicantSummary _summary({
  int total = 0,
  int awaiting = 0,
  int accepted = 0,
  int completed = 0,
  int byCaregiver = 0,
  List<ApplicantRejecter> byEmployer = const [],
}) =>
    ApplicantSummary(
      total: total,
      awaiting: awaiting,
      accepted: accepted,
      completed: completed,
      rejectedByCaregiver: byCaregiver,
      rejectedByEmployer: byEmployer,
    );

Future<void> _pump(WidgetTester tester, ApplicantSummary? s) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: ApplicantSummaryLine(summary: s))));

void main() {
  testWidgets('names who rejected, marking admins and the caregiver themselves', (tester) async {
    await _pump(
      tester,
      _summary(total: 4, accepted: 1, byCaregiver: 1, byEmployer: const [
        ApplicantRejecter(name: 'Super Admin', role: 'super_admin'),
        ApplicantRejecter(name: 'Hansa', role: 'individual'),
      ]),
    );
    expect(find.textContaining('4 applicants'), findsOneWidget);
    expect(find.textContaining('1 accepted'), findsOneWidget);
    expect(find.textContaining('3 rejected (Super Admin (admin), Hansa, caregiver)'), findsOneWidget);
  });

  testWidgets('repeated rejecters collapse to a count', (tester) async {
    await _pump(
      tester,
      _summary(total: 2, byEmployer: const [
        ApplicantRejecter(name: 'Hansa', role: 'individual'),
        ApplicantRejecter(name: 'Hansa', role: 'individual'),
      ]),
    );
    expect(find.textContaining('2 rejected (Hansa x2)'), findsOneWidget);
  });

  testWidgets('shows a plain message when nobody has applied, and nothing without data', (tester) async {
    await _pump(tester, _summary());
    expect(find.text('No applicants yet'), findsOneWidget);
    await _pump(tester, null);
    expect(find.byType(Text), findsNothing);
  });

  test('parses the API shape', () {
    final s = ApplicantSummary.fromJson({
      'total': 3,
      'awaiting': 0,
      'accepted': 1,
      'completed': 0,
      'rejected_by_caregiver': 0,
      'rejected_by_employer': [
        {'name': 'Hansa', 'role': 'individual'},
      ],
    });
    expect(s.rejected, 1);
    expect(s.rejectedByEmployer.single.name, 'Hansa');
  });
}
