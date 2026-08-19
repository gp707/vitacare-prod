import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/features/organisation/screens/post_organisation_requirement_screen.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class _FakeOrganisationRepository extends OrganisationRepository {
  final ApiException? createError;
  bool createCalled = false;
  String? capturedTypeOfNurse;
  bool? capturedAccommodation;
  bool? capturedFood;
  String? capturedSpecialSkills;

  _FakeOrganisationRepository({this.createError}) : super(Dio());

  @override
  Future<OrganisationRequirementModel> createRequirement({
    required String typeOfNurse,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
  }) async {
    createCalled = true;
    capturedTypeOfNurse = typeOfNurse;
    capturedAccommodation = accommodationProvided;
    capturedFood = foodProvided;
    capturedSpecialSkills = specialSkills;
    if (createError != null) throw createError!;
    return OrganisationRequirementModel.fromJson({
      'id': 'req-1',
      'requirement_number': 1,
      'posted_by': 'org-1',
      'type_of_nurse': typeOfNurse,
      'frequency_of_care': null,
      'salary_amount': null,
      'accommodation_provided': accommodationProvided,
      'food_provided': foodProvided,
      'status': 'pending_review',
      'posted_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pump(WidgetTester tester, _FakeOrganisationRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [organisationRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: PostOrganisationRequirementScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Submit is always tappable; tapping it with no type of nurse selected highlights it and does not submit',
      (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Please select a type'), findsOneWidget);
    expect(repo.createCalled, isFalse);
  });

  testWidgets('submits with type of nurse selected, accommodation/food/special skills as entered', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse (RN)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Accommodation provided?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Special skills required (optional)'),
      'Wound care experience',
    );

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.capturedTypeOfNurse, 'registered_nurse');
    expect(repo.capturedAccommodation, isTrue);
    expect(repo.capturedFood, isFalse);
    expect(repo.capturedSpecialSkills, 'Wound care experience');
  });

  testWidgets('shows the server error message on submission failure', (tester) async {
    final repo = _FakeOrganisationRepository(
      createError: const ApiException(code: 'JOB_010', message: 'Your account is blocked from posting new requirements'),
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General Duty Assistant (GDA)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Your account is blocked from posting new requirements'), findsOneWidget);
  });
}
