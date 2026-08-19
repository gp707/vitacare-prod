import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';
import 'package:caregiver_app/features/organisation_openings/screens/organisation_openings_screen.dart';

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 7,
  int? salaryAmount = 40000,
  String? frequencyOfCare = 'monthly',
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'frequency_of_care': frequencyOfCare,
    'salary_amount': salaryAmount,
    'start_date': null,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Post-surgery wound care',
    'status': 'active',
    'posted_at': '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
  });
}

class _FakeOrganisationOpeningsRepository extends OrganisationOpeningsRepository {
  List<OrganisationRequirementModel> requirements;
  final ApiException? listError;
  String? appliedWith;
  int listCallCount = 0;

  _FakeOrganisationOpeningsRepository(this.requirements, {this.listError}) : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> listActive() async {
    listCallCount++;
    if (listError != null) throw listError!;
    return requirements;
  }

  @override
  Future<String> apply(String requirementId, String status) async {
    appliedWith = status;
    return status;
  }
}

Future<void> _pump(WidgetTester tester, _FakeOrganisationOpeningsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(400, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [organisationOpeningsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: OrganisationOpeningsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when there are no active openings', (tester) async {
    await _pump(tester, _FakeOrganisationOpeningsRepository([]));
    expect(find.textContaining('No organisation openings right now'), findsOneWidget);
  });

  testWidgets('shows requirement details: org name, location, type of nurse, salary, accommodation/food',
      (tester) async {
    await _pump(tester, _FakeOrganisationOpeningsRepository([_requirement()]));

    expect(find.text('Requirement #7'), findsOneWidget);
    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('Hospital · Bangalore · Indiranagar'), findsOneWidget);
    expect(find.text('₹40000/month'), findsOneWidget);
    expect(find.text('Registered Nurse (RN)'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Post-surgery wound care'), findsOneWidget);
  });

  testWidgets('shows the salary unit as /day for a daily requirement', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationOpeningsRepository([_requirement(frequencyOfCare: 'daily')]),
    );
    expect(find.text('₹40000/day'), findsOneWidget);
  });

  testWidgets('tapping Apply calls the repository with applied', (tester) async {
    final repo = _FakeOrganisationOpeningsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(repo.appliedWith, 'applied');
  });

  testWidgets('tapping Reject calls the repository with rejected', (tester) async {
    final repo = _FakeOrganisationOpeningsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(repo.appliedWith, 'rejected');
  });

  testWidgets('shows the server error message on load failure', (tester) async {
    final repo = _FakeOrganisationOpeningsRepository(
      [],
      listError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
    );
    await _pump(tester, repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });
}
