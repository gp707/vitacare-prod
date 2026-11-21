import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/agreed_terms_box.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/job_detail_card.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

OrganisationRequirementModel _req({int? min, int? max, String? unit}) => OrganisationRequirementModel.fromJson({
      'id': 'r1',
      'requirement_number': 574,
      'posted_by': 'u1',
      'type_of_nurse': 'registered_nurse',
      'accommodation_provided': true,
      'food_provided': true,
      'number_of_vacancies': 2,
      'status': 'active',
      'posted_at': '2026-11-21T10:00:00Z',
      'organisation_name': 'City Hospital',
      'organisation_type': 'hospital',
      'city': 'bangalore',
      'salary_min': min,
      'salary_max': max,
      'salary_unit': unit,
    });

void main() {
  group('the salary range as a caregiver sees it', () {
    testWidgets('SalaryRangeLine shows the label with a rupee icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SalaryRangeLine(label: '₹20,000 – ₹30,000 per month'))));
      expect(find.text('₹20,000 – ₹30,000 per month'), findsOneWidget);
      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    });

    testWidgets('the full-detail page of a requirement shows the range when there is one', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RequirementFullDetailScreen(requirement: _req(min: 20000, max: 30000, unit: 'monthly')),
      ));
      expect(find.byKey(const Key('org-salary-range')), findsOneWidget);
      expect(find.text('₹20,000 – ₹30,000 per month'), findsOneWidget);
    });

    testWidgets('and shows nothing about salary when the organisation gave no range', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RequirementFullDetailScreen(requirement: _req())));
      expect(find.byKey(const Key('org-salary-range')), findsNothing);
    });
  });

  group('what the organisation agreed', () {
    testWidgets('the box is titled "Agreed with the organisation" for an organisation, "the family" by default', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AgreedTermsBox(title: 'Agreed with the organisation', salary: 25000, perUnit: 'month', startDate: '2026-12-01'),
            AgreedTermsBox(salary: 800, perUnit: 'day', startDate: '2026-11-20'),
          ]),
        ),
      ));
      expect(find.text('Agreed with the organisation'), findsOneWidget);
      expect(find.text('Agreed with the family'), findsOneWidget);
      expect(find.text('Salary: ₹25,000 per month'), findsOneWidget);
    });

    MyApplicationModel app() => MyApplicationModel.fromJson({
          'status': 'accepted',
          'decided_by_admin': false,
          'accepted_at': '2026-11-01T10:00:00Z',
          'applied_at': '2026-10-30T10:00:00Z',
          'agreement_history': [
            {'salary': 20000, 'unit': 'monthly', 'start_date': '2026-11-25', 'at': '2026-11-17T10:00:00Z'},
            {'salary': 25000, 'unit': 'monthly', 'start_date': '2026-12-01', 'at': '2026-11-21T12:00:00Z'},
          ],
        });

    testWidgets('the caregiver\'s log says the changes were made "by the organisation" for an organisation requirement', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ApplicationTimeline(app(), agreedBy: 'the organisation'))),
      ));
      await tester.tap(find.text('Show Activity Log'));
      await tester.pump();
      expect(find.textContaining('Salary and start date entered by the organisation'), findsOneWidget);
      expect(find.textContaining('Salary and start date changed by the organisation'), findsOneWidget);
      expect(find.textContaining('by the family'), findsNothing);
      expect(find.text('₹25,000 per month, starts 1 Dec 2026'), findsOneWidget);
    });

    testWidgets('and by "the family" for a patient\'s job (unchanged default)', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApplicationTimeline(app())))));
      await tester.tap(find.text('Show Activity Log'));
      await tester.pump();
      expect(find.textContaining('entered by the family'), findsOneWidget);
    });
  });
}
