import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/post_requirement_screen.dart';

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? createError;
  bool createCalled = false;
  CareReceiverInput? capturedCareReceiver;
  String? capturedCity;
  String? capturedArea;
  String? capturedDutyType;
  List<String>? capturedLanguages;

  _FakeIndividualRepository({this.createError}) : super(Dio());

  @override
  Future<JobModel> createRequirement({
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    createCalled = true;
    capturedCareReceiver = careReceiver;
    capturedCity = city;
    capturedArea = area;
    capturedDutyType = dutyType;
    capturedLanguages = languages;
    if (createError != null) throw createError!;
    return JobModel.fromJson({
      'id': 'job-1',
      'job_number': 1,
      'city': city,
      'duty_type': dutyType,
      'frequency_of_care': null,
      'languages': languages,
      'salary_amount': null,
      'status': 'pending_review',
      'posted_by': 'individual-1',
      'posted_at': '2026-08-01T10:00:00Z',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pumpTall(WidgetTester tester, _FakeIndividualRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(400, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [individualRepositoryProvider.overrideWithValue(repo)],
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

  await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
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
    expect(find.text('Select at least one language'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
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
    expect(repo.capturedLanguages, ['hindi']);
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
}
