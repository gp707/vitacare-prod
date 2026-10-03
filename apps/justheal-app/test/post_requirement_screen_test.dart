import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/patient_hospital/core/duty_requirements/duty_requirements_repository.dart';
import 'package:nursenow_app/patient_hospital/core/individual_messages/individual_messages_repository.dart';
import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/rate_card/rate_card_repository.dart';
import 'package:nursenow_app/patient_hospital/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/individual/screens/post_requirement_screen.dart';

/// Always exactly one row ("Care") per frequency, matching the live shape.
RateCardModel _rateCard({
  required String frequencyOfCare,
  required String companion,
  String bedside = 'BEDSIDE_RATE',
  String critical = 'CRITICAL_RATE',
}) =>
    RateCardModel(
      frequencyOfCare: frequencyOfCare,
      title: 'Salary Guidelines',
      columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
      rowLabels: const ['Care'],
      cells: [
        [companion, bedside, critical],
      ],
    );

/// Covers both frequencies with a Companion-tier default so
/// _fillMandatoryFields' default (independent/oral-feeding, Few Weeks ->
/// daily) auto-suggests a real, non-empty Salary without every test having
/// to type one in manually.
final _defaultRateCards = [
  _rateCard(frequencyOfCare: FrequencyOfCare.daily, companion: 'DAILY_COMPANION_RATE'),
  _rateCard(frequencyOfCare: FrequencyOfCare.monthly, companion: 'MONTHLY_COMPANION_RATE'),
];

class _FakeRateCardRepository extends RateCardRepository {
  final List<RateCardModel>? result;
  final Object? error;

  _FakeRateCardRepository({this.result, this.error}) : super(Dio());

  @override
  Future<List<RateCardModel>> get() async {
    if (error != null) throw error!;
    return result!;
  }
}

class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  _FakeIndividualMessagesRepository() : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async => const [];
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => ScopeOfWorkModel(
        companionCare: const ['Companion bullet'],
        bedsideCare: const ['Bedside bullet'],
        criticalCare: const ['Critical bullet'],
      );
}

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  _FakeDutyRequirementsRepository() : super(Dio());

  @override
  Future<DutyRequirementsModel> get() async => const DutyRequirementsModel(
        liveIn: ['Live-in bullet'],
        dayDuty: ['Day-duty bullet'],
        nightDuty: ['Night-duty bullet'],
      );
}

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? createError;
  bool createCalled = false;
  CareReceiverInput? capturedCareReceiver;
  String? capturedCity;
  String? capturedArea;
  String? capturedDutyType;
  String? capturedCareDuration;
  List<String>? capturedLanguages;
  String? capturedFrequencyOfCare;
  String? capturedSalaryAmount;

  _FakeIndividualRepository({this.createError}) : super(Dio());

  // Only exercised via MessagesBellButton, embedded in this screen's AppBar
  // — irrelevant to what this file actually tests (posting a requirement),
  // so both return empty rather than hitting the real network.
  @override
  Future<List<JobModel>> listMyRequirements() async => const [];

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => const [];

  @override
  Future<JobModel> createRequirement({
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required String careDuration,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    required String frequencyOfCare,
    required String salaryAmount,
  }) async {
    createCalled = true;
    capturedCareReceiver = careReceiver;
    capturedCity = city;
    capturedArea = area;
    capturedDutyType = dutyType;
    capturedCareDuration = careDuration;
    capturedLanguages = languages;
    capturedFrequencyOfCare = frequencyOfCare;
    capturedSalaryAmount = salaryAmount;
    if (createError != null) throw createError!;
    return JobModel.fromJson({
      'id': 'job-1',
      'city': city,
      'duty_type': dutyType,
      'frequency_of_care': frequencyOfCare,
      'languages': languages,
      'salary_amount': salaryAmount,
      'status': 'pending_review',
      'posted_by': 'individual-1',
      'posted_at': '2026-08-01T10:00:00Z',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pumpTall(
  WidgetTester tester,
  _FakeIndividualRepository repo, {
  List<RateCardModel>? rateCards,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 4200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        individualRepositoryProvider.overrideWithValue(repo),
        rateCardRepositoryProvider.overrideWithValue(
          _FakeRateCardRepository(result: rateCards ?? _defaultRateCards),
        ),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
        individualMessagesRepositoryProvider.overrideWithValue(_FakeIndividualMessagesRepository()),
        localStorageProvider.overrideWithValue(localStorage),
      ],
      child: const MaterialApp(home: PostRequirementScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillMandatoryFields(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '74');
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, "Patient's Gender (Mandatory)"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Female').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), '58');

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bangalore').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('24Hrs - Live In').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(OutlinedButton, 'Select date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Need for Few Weeks').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Independent/minimal support').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Oral feeding').last);
  await tester.pumpAndSettle();

}

void main() {
  testWidgets(
      'Submit is always tappable; tapping it with every mandatory field empty highlights all of them in red and does not submit',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Age is required (1-120)'), findsOneWidget);
    expect(find.text('Please select a gender'), findsOneWidget);
    expect(find.text('Weight is required (1-300 kg)'), findsOneWidget);
    expect(find.text('Please select a city'), findsOneWidget);
    expect(find.text('Area is required'), findsOneWidget);
    expect(find.text('Please select duty hours'), findsOneWidget);
    expect(find.text('Select a preferred start date'), findsOneWidget);
    expect(find.text('Please select how long care is needed'), findsOneWidget);
    // Salary hasn't appeared yet — Duration/Toilet Assistance/Feeding
    // Assistance are all still unfilled, so the bar shows its placeholder
    // hint instead of an input with "Salary is required".
    expect(find.text('Salary is required'), findsNothing);
    expect(
      find.textContaining('Salary will appear here once'),
      findsOneWidget,
    );
    expect(repo.createCalled, isFalse);
  });

  testWidgets('tapping Submit with only Area missing does not submit and moves focus into Area', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '74');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, "Patient's Gender (Mandatory)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), '58');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();
    // Area deliberately left empty.
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24Hrs - Live In').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Few Weeks').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('Area is required'), findsOneWidget);
    expect(repo.createCalled, isFalse);
    // Area is the only thing missing, so it's the one that gets focused —
    // the literal cursor-to-first-invalid behavior.
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.focusNode!.hasFocus, isTrue);
  });

  group('Area character-limit note', () {
    testWidgets('shows a declining "characters remaining" count as Area is typed, not yet red', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);

      expect(find.text('32 characters remaining (max 32 characters)'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');
      await tester.pump();

      expect(find.text('21 characters remaining (max 32 characters)'), findsOneWidget);
      final note = tester.widget<Text>(find.text('21 characters remaining (max 32 characters)'));
      expect(note.style?.color, isNot(AppColors.error));
    });

    testWidgets('turns red and counts over-the-limit characters once Area is typed past 32, without blocking input',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);

      final longArea = 'A' * 40;
      await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), longArea);
      await tester.pump();

      // Not blocked — the field itself still holds all 40 characters.
      final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
      expect(areaField.controller?.text, longArea);

      expect(find.text('8 characters over the 32 character limit'), findsOneWidget);
      final note = tester.widget<Text>(find.text('8 characters over the 32 character limit'));
      expect(note.style?.color, AppColors.error);
    });
  });

  testWidgets('submits with the hard-required fields filled, defaulting the rest server-side', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await _fillMandatoryFields(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.capturedCareReceiver!.age, 74);
    expect(repo.capturedCareReceiver!.gender, 'female');
    expect(repo.capturedCareReceiver!.weightKg, 58);
    expect(repo.capturedCity, 'bangalore');
    expect(repo.capturedArea, 'Indiranagar');
    expect(repo.capturedDutyType, 'live_in');
    expect(repo.capturedCareDuration, 'few_weeks');
    expect(repo.capturedLanguages, <String>[]);
    // Derived from care_duration ('few_weeks' -> daily) and the Rate
    // Card's Companion-tier daily suggestion (independent/oral-feeding
    // defaults, no medical condition).
    expect(repo.capturedFrequencyOfCare, 'daily');
    expect(repo.capturedSalaryAmount, 'DAILY_COMPANION_RATE');
  });

  testWidgets('shows the server error message (e.g. JOB_009) when submission fails', (tester) async {
    final repo = _FakeIndividualRepository(
      createError: const ApiException(code: 'JOB_009', message: 'You already have a requirement in progress'),
    );
    await _pumpTall(tester, repo);

    await _fillMandatoryFields(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(find.text('You already have a requirement in progress'), findsOneWidget);
  });

  testWidgets(
      'warns that a male patient requesting a female caregiver reduces match chances by ~90%, without blocking submission',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '74');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, "Patient's Gender (Mandatory)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), '58');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24Hrs - Live In').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Few Weeks').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Independent/minimal support').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oral feeding').last);
    await tester.pumpAndSettle();

    // No warning yet — no caregiver gender preference set.
    expect(find.textContaining('reduces your chances'), findsNothing);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Preferred Caregiver Gender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('reduces your chances of getting matched by about 90%'), findsOneWidget);

    await tester.ensureVisible(find.text('Submit for Review'));
    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue, reason: 'the warning is advisory only and never blocks submission');
  });

  testWidgets('does not show the warning for a female patient requesting a female caregiver', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);
    await _fillMandatoryFields(tester); // patient gender = Female

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Preferred Caregiver Gender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('reduces your chances'), findsNothing);
  });

  testWidgets('shows no short-term-duration warning while Duration Care is Needed is untouched', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    expect(find.text('Short-term requirement'), findsNothing);
  });

  testWidgets('shows the short-term-duration warning for Need for few Days', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for few Days').last);
    await tester.pumpAndSettle();

    expect(find.text('Short-term requirement'), findsOneWidget);
    expect(find.textContaining('Many nurses do not accept short-term assignments'), findsOneWidget);
  });

  testWidgets('shows the short-term-duration warning for Need for Few Weeks', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Few Weeks').last);
    await tester.pumpAndSettle();

    expect(find.text('Short-term requirement'), findsOneWidget);
  });

  testWidgets('hides the short-term-duration warning once switched to Need for Minimum a Month', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for few Days').last);
    await tester.pumpAndSettle();
    expect(find.text('Short-term requirement'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Minimum a Month').last);
    await tester.pumpAndSettle();

    expect(find.text('Short-term requirement'), findsNothing);
  });

  testWidgets(
      'groups fields under three headed sections — Patient Details, Care Preferences, and Nurse Fee '
      'Guidance — and no longer offers Mobility or the free-text "more details" field',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);

    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    // Nurse Fee Guidance is gone entirely — Salary lives in the sticky top
    // bar instead, and Frequency of Care is no longer shown at all.
    expect(find.text('Nurse Fee Guidance'), findsNothing);
    expect(find.text('Frequency of Care'), findsNothing);
    // Duration/Toilet Assistance/Feeding Assistance are all still unfilled
    // at this point, so the Salary bar shows its placeholder hint, not the
    // input or the derived-tier line.
    expect(find.textContaining('Salary will appear here once'), findsOneWidget);
    expect(find.textContaining('this appears to be a'), findsNothing);
    // The old section headings are gone — everything now lives under the
    // new ones.
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('Care Location'), findsNothing);
    // Mobility was removed from the product entirely.
    expect(find.text('Mobility (optional)'), findsNothing);
    // The free-text "more details" field was removed too.
    expect(find.text('More details you want to share about patient (optional)'), findsNothing);
    // Feeding Type is relabeled per the new grouping, and mandatory.
    expect(find.text('Feeding/Medicine Assistance (Mandatory)'), findsOneWidget);
    // Toilet Assistance is now a mandatory single-select dropdown, not an
    // optional multi-select chip group.
    expect(find.text('Toilet Assistance (Mandatory)'), findsOneWidget);

    // Fill in the 3 fields Salary is gated on so it actually appears, to
    // check its position/derived-tier line and the rest of the field order.
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Independent/minimal support').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oral feeding').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Few Weeks').last);
    await tester.pumpAndSettle();

    // Independent toilet assistance + oral feeding -> Companion Care.
    expect(find.textContaining('this appears to be a'), findsOneWidget);
    expect(find.text('Companion Care'), findsOneWidget);

    // Patient Details' own fields appear before Care Location's fields
    // moved into it (city/area) — Care Preferences' fields (hours care
    // needed, start date) come after — matching the new order. The Salary
    // bar sits above all of this, pinned below the AppBar.
    final salaryTop = tester
        .getTopLeft(find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith('Salary (₹/')))
        .dy;
    final patientDetailsTop = tester.getTopLeft(find.text('Patient Details')).dy;
    final carePreferencesTop = tester.getTopLeft(find.text('Care Preferences')).dy;
    final cityFieldTop = tester.getTopLeft(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)')).dy;
    final dutyTypeFieldTop =
        tester.getTopLeft(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)')).dy;
    expect(salaryTop, lessThan(patientDetailsTop));
    expect(patientDetailsTop, lessThan(cityFieldTop));
    expect(cityFieldTop, lessThan(carePreferencesTop));
    expect(carePreferencesTop, lessThan(dutyTypeFieldTop));

    // Tapping the tier name opens the Scope of Work dialog for that tier.
    await tester.tap(find.text('Companion Care'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Companion Care'), findsOneWidget);
  });

  testWidgets('submitting no longer sends mobility or description', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo);
    await _fillMandatoryFields(tester);

    await tester.tap(find.text('Submit for Review'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    final sentBody = repo.capturedCareReceiver!.toJson();
    expect(sentBody.containsKey('mobility'), isFalse);
  });

  group('Frequency of Care and Salary — derived, not admin-set', () {
    testWidgets('Frequency of Care is no longer shown as its own field — only the Salary unit reflects it',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester); // picks 'Need for Few Weeks' -> daily

      expect(find.text('Frequency of Care'), findsNothing);
      expect(find.text('Salary (₹/day) — Guidance only'), findsOneWidget);
    });

    testWidgets('the Salary unit switches to ₹/month when Duration is changed to Long Term', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Need for Long Term').last);
      await tester.pumpAndSettle();

      expect(find.text('Salary (₹/month) — Guidance only'), findsOneWidget);
    });

    testWidgets('Salary is pre-filled with the Companion daily suggestion once Duration is picked', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester);

      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);
    });

    testWidgets('Salary refreshes to the Critical suggestion when toilet assistance is bumped up', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        rateCards: [
          _rateCard(frequencyOfCare: FrequencyOfCare.daily, companion: 'DAILY_COMPANION_RATE', critical: 'DAILY_CRITICAL_RATE'),
        ],
      );
      await _fillMandatoryFields(tester);
      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catheter support').last);
      await tester.pumpAndSettle();

      expect(find.text('DAILY_CRITICAL_RATE'), findsOneWidget);
    });

    testWidgets('Salary is not an editable field — just bold standout text, with guidance above it', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester);
      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      // No TextField anywhere carries the Salary label — there's nothing
      // to tap into or type over, it's plain text now.
      expect(
        find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Salary')),
        findsNothing,
      );

      expect(
        find.text(
          'This is just a guidance, you must discuss it directly with caregivers. Fees are paid directly to the Nurse/Caregivers.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows a placeholder dash (not a crash) when the Rate Card has no matching suggestion',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo, rateCards: const []);
      await _fillMandatoryFields(tester);

      expect(find.text('—'), findsOneWidget);
    });
  });

  group('"None" option — Feeding/Medicine Assistance and Toilet Assistance', () {
    testWidgets('None (Feeding/Medicine Assistance) submits as oral_feeding and suggests the same Salary as '
        'Oral feeding', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester); // picks 'Oral feeding' by default

      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();

      // Same tier/Salary suggestion as 'Oral feeding' — None doesn't bump
      // the derived care tier.
      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.tap(find.text('Submit for Review'));
      await tester.pumpAndSettle();

      expect(repo.createCalled, isTrue);
      expect(repo.capturedCareReceiver?.feedingType, FeedingType.oralFeeding);
    });

    testWidgets('None (Toilet Assistance) submits as [independent] and suggests the same Salary as '
        'Independent/minimal support', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(tester, repo);
      await _fillMandatoryFields(tester); // picks 'Independent/minimal support' by default

      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();

      // Same tier/Salary suggestion as 'Independent/minimal support' — None
      // doesn't bump the derived care tier.
      expect(find.text('DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.tap(find.text('Submit for Review'));
      await tester.pumpAndSettle();

      expect(repo.createCalled, isTrue);
      expect(repo.capturedCareReceiver?.toiletAssistance, [ToiletAssistance.independent]);
    });
  });
}
