import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/shared/state/read_only_admin.dart';
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/organisation_requirements/widgets/requirement_widgets.dart';

class _FakeOrgRepo implements AdminOrganisationsRepository {
  @override
  Future<AdminOrganisationListItem> getDetail(String userId) async => AdminOrganisationListItem.fromJson({
        'user_id': userId,
        'full_name': 'Maria',
        'phone': '+919800000001',
        'organisation_name': 'Test Hospital',
        'organisation_type': 'hospital',
        'city': 'bangalore',
        'area': 'x',
        'is_active': true,
        'is_job_posting_blocked': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AdminOrganisationRequirement _req(Map<String, dynamic> extra) => AdminOrganisationRequirement.fromJson({
      'id': 'r1',
      'posted_by': 'org-user-1',
      'requirement_number': 501,
      'status': 'active',
      'type_of_nurse': 'registered_nurse',
      'number_of_vacancies': 1,
      'accommodation_provided': false,
      'food_provided': false,
      'duration_type': 'short_term',
      'posted_at': '2026-01-01T00:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'organisation_name': 'Test Hospital',
      ...extra,
    });

Future<void> _pump(WidgetTester tester, AdminOrganisationRequirement req) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      adminOrganisationsRepositoryProvider.overrideWithValue(_FakeOrgRepo()),
      isReadOnlyAdminProvider.overrideWithValue(false),
    ],
    child: MaterialApp(home: Scaffold(body: RequirementReadOnlyDialog(requirement: req, onEdit: () {}))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin sees the salary range an organisation gave, per month', (tester) async {
    await _pump(tester, _req({'salary_min': 20000, 'salary_max': 30000, 'salary_unit': 'monthly'}));
    expect(find.text('Salary Range'), findsOneWidget);
    expect(find.text('₹20,000 – ₹30,000 per month'), findsOneWidget);
  });

  testWidgets('per day, and equal ends read as one figure', (tester) async {
    await _pump(tester, _req({'salary_min': 900, 'salary_max': 900, 'salary_unit': 'daily'}));
    expect(find.text('₹900 per day'), findsOneWidget);
  });

  testWidgets('a dash when the organisation gave no range', (tester) async {
    await _pump(tester, _req({}));
    expect(find.text('Salary Range'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('per month'), findsNothing);
  });
}
