import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/organisation_requirements/widgets/requirement_widgets.dart';

class _FakeOrgRepo implements AdminOrganisationsRepository {
  String? notes = 'call after 5pm';
  final saved = <String?>[];

  @override
  Future<AdminOrganisationListItem> getDetail(String userId) async =>
      AdminOrganisationListItem.fromJson({
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
        'notes': notes,
      });

  @override
  Future<void> upsertNotes(String userId, String? n) async {
    saved.add(n);
    notes = n;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('shows the organisation note and saves edits to the same note',
      (tester) async {
    final repo = _FakeOrgRepo();
    final req = AdminOrganisationRequirement.fromJson({
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
    });
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    await tester.pumpWidget(ProviderScope(
      overrides: [adminOrganisationsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: RequirementReadOnlyDialog(requirement: req, onEdit: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('call after 5pm'), findsOneWidget);

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'updated note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.saved, ['updated note']);
    expect(find.text('updated note'), findsOneWidget);
  });
}
