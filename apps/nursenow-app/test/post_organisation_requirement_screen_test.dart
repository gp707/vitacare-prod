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
  String? capturedTypeOfNurseOther;
  bool? capturedAccommodation;
  bool? capturedFood;
  String? capturedSpecialSkills;
  int? capturedNumberOfVacancies;
  String? capturedPreferredGender;
  String? capturedDurationType;

  _FakeOrganisationRepository({this.createError}) : super(Dio());

  @override
  Future<OrganisationRequirementModel> createRequirement({
    required String typeOfNurse,
    String? typeOfNurseOther,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
    int? numberOfVacancies,
    String? preferredGender,
    required String durationType,
  }) async {
    createCalled = true;
    capturedTypeOfNurse = typeOfNurse;
    capturedTypeOfNurseOther = typeOfNurseOther;
    capturedAccommodation = accommodationProvided;
    capturedFood = foodProvided;
    capturedSpecialSkills = specialSkills;
    capturedNumberOfVacancies = numberOfVacancies;
    capturedPreferredGender = preferredGender;
    capturedDurationType = durationType;
    if (createError != null) throw createError!;
    return OrganisationRequirementModel.fromJson({
      'id': 'req-1',
      'requirement_number': 1,
      'posted_by': 'org-1',
      'type_of_nurse': typeOfNurse,
      'type_of_nurse_other': typeOfNurseOther,
      'accommodation_provided': accommodationProvided,
      'food_provided': foodProvided,
      'number_of_vacancies': numberOfVacancies ?? 1,
      'preferred_gender': preferredGender,
      'duration_type': durationType,
      'status': 'pending_review',
      'posted_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _selectDuration(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Duration (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Short Term (Few Days/Weeks Only)').last);
  await tester.pumpAndSettle();
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
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Accommodation provided?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'Wound care experience',
    );

    await _selectDuration(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.capturedTypeOfNurse, 'registered_nurse');
    expect(repo.capturedAccommodation, isTrue);
    expect(repo.capturedFood, isFalse);
    expect(repo.capturedSpecialSkills, 'Wound care experience');
  });

  testWidgets('does not show the admin-review banner at the top of the form', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    expect(find.textContaining('An admin reviews every new requirement'), findsNothing);
  });

  testWidgets(
      'Special skills field has no hard maxLength — typing/pasting past ${Validation.specialSkillsMaxLength} '
      'characters is allowed, not silently truncated', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    final field =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Job description/Special Skills (optional)'));
    expect(field.maxLength, isNull);

    final overLimitText = 'a' * (Validation.specialSkillsMaxLength + 50);
    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      overLimitText,
    );
    await tester.pump();

    final controller = field.controller!;
    expect(controller.text.length, Validation.specialSkillsMaxLength + 50);
  });

  testWidgets(
      'shows a red border/error message immediately once past ${Validation.specialSkillsMaxLength} characters, '
      'and the entered/remaining count below the field', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'a' * 500,
    );
    await tester.pump();

    expect(
        find.text('500 entered · 500 characters remaining (max ${Validation.specialSkillsMaxLength} characters)'),
        findsOneWidget);
    expect(
      find.text('Please enter less than ${Validation.specialSkillsMaxLength} characters'),
      findsNothing,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'a' * (Validation.specialSkillsMaxLength + 30),
    );
    await tester.pump();

    expect(
      find.text('Please enter less than ${Validation.specialSkillsMaxLength} characters'),
      findsOneWidget,
    );
    expect(
      find.text(
          '${Validation.specialSkillsMaxLength + 30} entered · 30 characters over the ${Validation.specialSkillsMaxLength} character limit'),
      findsOneWidget,
    );
  });

  testWidgets('Submit is blocked while Special Skills is over the character limit', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();
    await _selectDuration(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'a' * (Validation.specialSkillsMaxLength + 1),
    );
    await tester.pump();

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isFalse);

    await tester.enterText(
      find.widgetWithText(TextField, 'Job description/Special Skills (optional)'),
      'a' * Validation.specialSkillsMaxLength,
    );
    await tester.pump();
    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
  });

  testWidgets('Number of Vacancies defaults to 1 and is sent as-is when untouched', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    expect(find.widgetWithText(TextField, 'Number of Vacancies (Mandatory)'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    await _selectDuration(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.capturedNumberOfVacancies, 1);
  });

  testWidgets('rejects a Number of Vacancies outside 1-49 without submitting', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Number of Vacancies (Mandatory)'), '50');
    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a number between 1 and 49'), findsOneWidget);
    expect(repo.createCalled, isFalse);
  });

  testWidgets('requires a free-text description when Type of Nurse is Others, and sends it', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Please specify the type of nurse/caregiver'), findsOneWidget);
    expect(repo.createCalled, isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Please specify (Mandatory)'), 'Physiotherapist');
    await _selectDuration(tester);
    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.capturedTypeOfNurse, 'others');
    expect(repo.capturedTypeOfNurseOther, 'Physiotherapist');
  });

  testWidgets('does not show the "Please specify" field for a non-Others type', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Please specify (Mandatory)'), findsNothing);
  });

  testWidgets('defaults Preferred Caregiver Gender to no preference (null) when left untouched', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    await _selectDuration(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();
    expect(repo.capturedPreferredGender, isNull);
  });

  testWidgets('sends the selected Preferred Caregiver Gender', (tester) async {
    final repo = _FakeOrganisationRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registered Nurse').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Preferred Caregiver Gender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    await _selectDuration(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();
    expect(repo.capturedPreferredGender, 'female');
  });

  testWidgets('shows the server error message on submission failure', (tester) async {
    final repo = _FakeOrganisationRepository(
      createError: const ApiException(code: 'JOB_010', message: 'Your account is blocked from posting new requirements'),
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auxiliary Nurse').last);
    await tester.pumpAndSettle();

    await _selectDuration(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Your account is blocked from posting new requirements'), findsOneWidget);
  });
}
