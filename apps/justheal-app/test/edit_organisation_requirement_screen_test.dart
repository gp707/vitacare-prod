import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/screens/edit_organisation_requirement_screen.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class _FakeOrganisationRepository extends OrganisationRepository {
  final ApiException? editError;
  bool editCalled = false;
  String? capturedRequirementId;
  String? capturedTypeOfNurse;
  String? capturedTypeOfNurseOther;
  bool? capturedAccommodation;
  bool? capturedFood;
  String? capturedSpecialSkills;
  int? capturedNumberOfVacancies;
  String? capturedPreferredGender;
  String? capturedDurationType;

  _FakeOrganisationRepository({this.editError}) : super(Dio());

  @override
  Future<OrganisationRequirementModel> editRequirement(
    String requirementId, {
    required String typeOfNurse,
    String? typeOfNurseOther,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
    required int numberOfVacancies,
    String? preferredGender,
    required String durationType,
  }) async {
    editCalled = true;
    capturedRequirementId = requirementId;
    capturedTypeOfNurse = typeOfNurse;
    capturedTypeOfNurseOther = typeOfNurseOther;
    capturedAccommodation = accommodationProvided;
    capturedFood = foodProvided;
    capturedSpecialSkills = specialSkills;
    capturedNumberOfVacancies = numberOfVacancies;
    capturedPreferredGender = preferredGender;
    capturedDurationType = durationType;
    if (editError != null) throw editError!;
    return _requirement(
      typeOfNurse: typeOfNurse,
      typeOfNurseOther: typeOfNurseOther,
      accommodationProvided: accommodationProvided,
      foodProvided: foodProvided,
      specialSkills: specialSkills,
      numberOfVacancies: numberOfVacancies,
      preferredGender: preferredGender,
      durationType: durationType,
    );
  }
}

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  String typeOfNurse = 'registered_nurse',
  String? typeOfNurseOther,
  bool accommodationProvided = true,
  bool foodProvided = false,
  String? specialSkills,
  int numberOfVacancies = 3,
  String? preferredGender,
  String durationType = 'short_term',
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': 1,
    'posted_by': 'org-1',
    'type_of_nurse': typeOfNurse,
    'type_of_nurse_other': typeOfNurseOther,
    'accommodation_provided': accommodationProvided,
    'food_provided': foodProvided,
    'special_skills': specialSkills,
    'number_of_vacancies': numberOfVacancies,
    'preferred_gender': preferredGender,
    'duration_type': durationType,
    'status': 'pending_review',
    'posted_at': '2026-08-01T10:00:00Z',
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeOrganisationRepository repo, {
  required OrganisationRequirementModel requirement,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [organisationRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: EditOrganisationRequirementScreen(requirement: requirement)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pre-fills every org-owned field from the existing requirement', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(
      tester,
      repo,
      requirement: _requirement(
        typeOfNurse: 'others',
        typeOfNurseOther: 'Wound care specialist',
        accommodationProvided: true,
        foodProvided: true,
        specialSkills: 'Fluent in Kannada',
        numberOfVacancies: 5,
        preferredGender: 'female',
        durationType: 'long_term',
      ),
    );

    expect(find.text('Others'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Please specify (Mandatory)'), findsOneWidget);
    expect(find.text('Wound care specialist'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Fluent in Kannada'), findsOneWidget);
    expect(find.text('Long Term'), findsOneWidget);

    final accommodationSwitch =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Accommodation provided?'));
    expect(accommodationSwitch.value, isTrue);
    final foodSwitch = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Food provided?'));
    expect(foodSwitch.value, isTrue);

    // No hard maxLength — the org can type/paste past the limit and see a
    // live red warning instead of being silently truncated.
    final specialSkillsField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Job description/Special Skills (optional)'));
    expect(specialSkillsField.maxLength, isNull);
  });

  testWidgets('saves changes and calls editRequirement with the requirement id', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo, requirement: _requirement(id: 'req-42'));

    await tester.enterText(
      find.widgetWithText(TextField, 'Number of Vacancies (Mandatory)'),
      '10',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editCalled, isTrue);
    expect(repo.capturedRequirementId, 'req-42');
    expect(repo.capturedNumberOfVacancies, 10);
    expect(repo.capturedTypeOfNurse, 'registered_nurse');
  });

  testWidgets('rejects a Number of Vacancies outside 1-49 without saving', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo, requirement: _requirement());

    await tester.enterText(find.widgetWithText(TextField, 'Number of Vacancies (Mandatory)'), '0');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a number between 1 and 49'), findsOneWidget);
    expect(repo.editCalled, isFalse);
  });

  testWidgets(
      'shows a red border/error message and blocks Save once Special Skills is typed/pasted past '
      '${Validation.specialSkillsMaxLength} characters', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo, requirement: _requirement());

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'a' * (Validation.specialSkillsMaxLength + 20),
    );
    await tester.pump();

    expect(
      find.text('Please enter less than ${Validation.specialSkillsMaxLength} characters'),
      findsOneWidget,
    );
    expect(
      find.text(
          '${Validation.specialSkillsMaxLength + 20} entered · 20 characters over the ${Validation.specialSkillsMaxLength} character limit'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(repo.editCalled, isFalse);
  });

  testWidgets('requires a free-text description when switching Type of Nurse to Others', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo, requirement: _requirement());

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Please specify the type of nurse/caregiver'), findsOneWidget);
    expect(repo.editCalled, isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Please specify (Mandatory)'), 'Physiotherapist');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editCalled, isTrue);
    expect(repo.capturedTypeOfNurseOther, 'Physiotherapist');
  });

  testWidgets('shows the server error message on save failure', (tester) async {
    final repo = _FakeOrganisationRepository(
      editError: const ApiException(code: 'JOB_014', message: 'This requirement cannot be edited while it has an active application'),
    );
    await _pump(tester, repo, requirement: _requirement());

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('This requirement cannot be edited while it has an active application'),
      findsOneWidget,
    );
  });
}
