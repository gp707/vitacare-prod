import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/rate_card/rate_card_repository.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/edit_requirement_screen.dart';

Map<String, dynamic> _careReceiverJson({
  List<String> toiletAssistance = const ['independent'],
  String feedingType = 'oral_feeding',
  bool hasMedicalCondition = false,
}) =>
    {
      'id': 'cr-1',
      'age': 74,
      'gender': 'female',
      'weight_kg': 58,
      'communication': 'verbal',
      'feeding_type': feedingType,
      'has_medical_condition': hasMedicalCondition,
      'medical_conditions': hasMedicalCondition ? ['diabetes'] : <String>[],
      'toilet_assistance': toiletAssistance,
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    };

JobModel _requirement({
  String id = 'job-1',
  String? frequencyOfCare,
  String? salaryAmount,
  String careDuration = 'few_weeks',
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': id,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-09-01',
    'care_duration': careDuration,
    'languages': <String>['hindi'],
    'salary_amount': salaryAmount,
    'status': frequencyOfCare == null ? 'pending_review' : 'active',
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'care_receiver': careReceiver ?? _careReceiverJson(),
  });
}

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

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? editError;
  bool editCalled = false;
  CareReceiverInput? capturedCareReceiver;
  String? capturedFrequencyOfCare;
  String? capturedSalaryAmount;

  _FakeIndividualRepository({this.editError}) : super(Dio());

  @override
  Future<JobModel> editRequirement(
    String jobId, {
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
    editCalled = true;
    capturedCareReceiver = careReceiver;
    capturedFrequencyOfCare = frequencyOfCare;
    capturedSalaryAmount = salaryAmount;
    if (editError != null) throw editError!;
    return JobModel.fromJson({
      'id': jobId,
      'city': city,
      'duty_type': dutyType,
      'frequency_of_care': frequencyOfCare,
      'languages': languages,
      'salary_amount': salaryAmount,
      'status': 'active',
      'posted_by': 'individual-1',
      'posted_at': '2026-08-01T10:00:00Z',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pumpTall(
  WidgetTester tester,
  _FakeIndividualRepository repo,
  JobModel requirement, {
  List<RateCardModel>? rateCards,
  Object? rateCardError,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 4200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        individualRepositoryProvider.overrideWithValue(repo),
        rateCardRepositoryProvider.overrideWithValue(
          _FakeRateCardRepository(result: rateCards ?? const [], error: rateCardError),
        ),
      ],
      child: MaterialApp(home: EditRequirementScreen(requirement: requirement)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'groups fields under headed sections — Patient Details, Care Preferences, and Nurse Fee '
      'Guidance (always shown now, not gated on a prior admin approval) — with pre-filled values, '
      'and no longer offers Mobility or the free-text "more details" field',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo, _requirement(frequencyOfCare: 'daily', salaryAmount: '28000'));

    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    expect(find.text('Nurse Fee Guidance'), findsOneWidget);
    expect(find.text('You can always negotiate with nurse staff.'), findsOneWidget);
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('Care Location'), findsNothing);
    expect(find.text('Mobility (optional)'), findsNothing);
    expect(find.text('More details you want to share about patient (optional)'), findsNothing);
    expect(find.text('Feeding/Medicine Assistance (Mandatory)'), findsOneWidget);
    expect(find.text('Toilet Assistance (Mandatory)'), findsOneWidget);

    // Pre-filled from the requirement.
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
    expect(find.text('74'), findsOneWidget);
    expect(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), findsOneWidget);
    expect(find.text('58'), findsOneWidget);
  });

  testWidgets('shows Nurse Fee Guidance even for a requirement never yet admin-reviewed', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo, _requirement());

    expect(find.text('Nurse Fee Guidance'), findsOneWidget);
  });

  group('Frequency of Care is derived from Duration Care is Needed, not manually picked', () {
    testWidgets('few_weeks derives to Daily, with no dropdown to pick it', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'monthly', salaryAmount: '9999', careDuration: 'few_weeks'),
      );

      expect(find.text('Frequency of Care'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
      // No mandatory-dropdown label for it anymore — it's derived, not picked.
      expect(find.text('Frequency of Care (Mandatory)'), findsNothing);
    });

    testWidgets('long_term derives to Monthly', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: '9999', careDuration: 'long_term'),
      );

      expect(find.text('Monthly'), findsOneWidget);
    });
  });

  group('Salary is pre-filled with the Rate Card suggestion for the derived tier/frequency', () {
    testWidgets('an independent/oral-feeding patient with few_weeks duration gets the Companion daily rate',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: '9999', careDuration: 'few_weeks'),
        rateCards: [
          _rateCard(frequencyOfCare: FrequencyOfCare.daily, companion: 'DAILY_COMPANION_RATE'),
          _rateCard(frequencyOfCare: FrequencyOfCare.monthly, companion: 'MONTHLY_COMPANION_RATE'),
        ],
      );

      expect(find.widgetWithText(TextField, 'DAILY_COMPANION_RATE'), findsOneWidget);
      expect(find.text('9999'), findsNothing);
    });

    testWidgets('a catheter-support patient gets the Critical rate for the derived frequency', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(
          frequencyOfCare: 'monthly',
          salaryAmount: '9999',
          careDuration: 'long_term',
          careReceiver: _careReceiverJson(toiletAssistance: const [ToiletAssistance.usesCatheter]),
        ),
        rateCards: [
          _rateCard(frequencyOfCare: FrequencyOfCare.monthly, companion: 'MONTHLY_COMPANION_RATE', critical: 'MONTHLY_CRITICAL_RATE'),
        ],
      );

      expect(find.widgetWithText(TextField, 'MONTHLY_CRITICAL_RATE'), findsOneWidget);
    });

    testWidgets('the pre-filled suggestion stays freely editable', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: '9999', careDuration: 'few_weeks'),
        rateCards: [_rateCard(frequencyOfCare: FrequencyOfCare.daily, companion: 'DAILY_COMPANION_RATE')],
      );
      expect(find.widgetWithText(TextField, 'DAILY_COMPANION_RATE'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'DAILY_COMPANION_RATE'), '35000 negotiable');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repo.capturedSalaryAmount, '35000 negotiable');
    });

    testWidgets(
        'refreshes the suggestion when toilet assistance changes to a higher tier, but stops refreshing '
        'once the patient has typed their own value', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(
          frequencyOfCare: 'daily',
          salaryAmount: '9999',
          careDuration: 'few_weeks',
          careReceiver: _careReceiverJson(), // independent/oral-feeding -> companion tier
        ),
        rateCards: [
          _rateCard(
            frequencyOfCare: FrequencyOfCare.daily,
            companion: 'DAILY_COMPANION_RATE',
            critical: 'DAILY_CRITICAL_RATE',
          ),
        ],
      );
      expect(find.widgetWithText(TextField, 'DAILY_COMPANION_RATE'), findsOneWidget);

      // Bumping toilet assistance to catheter support pushes the derived
      // tier to Critical — the still-auto-suggested field follows along.
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catheter support').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), findsOneWidget);

      // Once the patient types their own figure, further field changes
      // must not clobber it.
      await tester.enterText(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), '50000 my own number');
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diapers/bedside support').last);
      await tester.pumpAndSettle();
      expect(find.text('50000 my own number'), findsOneWidget);
    });

    testWidgets('falls back to the existing salary_amount when the Rate Card fetch fails', (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: '28000', careDuration: 'few_weeks'),
        rateCardError: Exception('network down'),
      );

      expect(find.widgetWithText(TextField, '28000'), findsOneWidget);
    });

    testWidgets('leaves the field empty (not a crash) when there is no existing salary and no suggestion resolves',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: null, careDuration: 'few_weeks'),
        rateCards: const [],
      );

      final salaryField = tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Salary'),
      ));
      expect(salaryField.controller?.text, '');
    });

    testWidgets('a blank salary blocks submission with a validation error, not a numeric-range message',
        (tester) async {
      final repo = _FakeIndividualRepository();
      await _pumpTall(
        tester,
        repo,
        _requirement(frequencyOfCare: 'daily', salaryAmount: '28000', careDuration: 'few_weeks'),
        rateCards: const [],
      );

      await tester.enterText(find.widgetWithText(TextField, '28000'), '');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Salary is required'), findsOneWidget);
      expect(repo.editCalled, isFalse);
    });
  });

  testWidgets('saving edits calls editRequirement without mobility or description, sending the derived frequency',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(
      tester,
      repo,
      _requirement(frequencyOfCare: 'monthly', salaryAmount: '28000', careDuration: 'few_weeks'),
      rateCards: const [],
    );

    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '80');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editCalled, isTrue);
    expect(repo.capturedCareReceiver!.age, 80);
    final sentBody = repo.capturedCareReceiver!.toJson();
    expect(sentBody.containsKey('mobility'), isFalse);
    // Derived from care_duration ('few_weeks' -> daily), not the
    // requirement's previous (monthly) frequency_of_care.
    expect(repo.capturedFrequencyOfCare, 'daily');
    expect(repo.capturedSalaryAmount, '28000');
  });

  testWidgets('shows a server error message when saving fails', (tester) async {
    final repo = _FakeIndividualRepository(
      editError: ApiException(message: 'Something went wrong', code: 'JOB_014'),
    );
    await _pumpTall(
      tester,
      repo,
      _requirement(frequencyOfCare: 'daily', salaryAmount: '28000'),
      rateCards: const [],
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });
}
