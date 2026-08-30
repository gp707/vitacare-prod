import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/edit_requirement_screen.dart';

final _careReceiverJson = {
  'id': 'cr-1',
  'age': 74,
  'gender': 'female',
  'weight_kg': 58,
  'communication': 'verbal',
  'feeding_type': 'oral_independent',
  'has_medical_condition': false,
  'medical_conditions': [],
  'toilet_assistance': ['independent'],
  'requires_vital_monitoring': false,
  'vital_monitoring_types': [],
};

JobModel _requirement({
  String id = 'job-1',
  String? frequencyOfCare,
  int? salaryAmount,
}) {
  return JobModel.fromJson({
    'id': id,
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-09-01',
    'languages': <String>['hindi'],
    'salary_amount': salaryAmount,
    'status': frequencyOfCare == null ? 'pending_review' : 'active',
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'care_receiver': _careReceiverJson,
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? editError;
  bool editCalled = false;
  CareReceiverInput? capturedCareReceiver;
  String? capturedFrequencyOfCare;
  int? capturedSalaryAmount;

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
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    String? frequencyOfCare,
    int? salaryAmount,
  }) async {
    editCalled = true;
    capturedCareReceiver = careReceiver;
    capturedFrequencyOfCare = frequencyOfCare;
    capturedSalaryAmount = salaryAmount;
    if (editError != null) throw editError!;
    return JobModel.fromJson({
      'id': jobId,
      'job_number': 42,
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

Future<void> _pumpTall(WidgetTester tester, _FakeIndividualRepository repo, JobModel requirement) async {
  await tester.binding.setSurfaceSize(const Size(400, 4200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [individualRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: EditRequirementScreen(requirement: requirement)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'groups fields under headed sections — Patient Details, Care Preferences, and (once approved) '
      'Frequency & Salary — with pre-filled values, and no longer offers Mobility or the free-text '
      '"more details" field',
      (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo, _requirement(frequencyOfCare: 'daily', salaryAmount: 28000));

    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    expect(find.text('Frequency & Salary'), findsOneWidget);
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('Care Location'), findsNothing);
    expect(find.text('Mobility (optional)'), findsNothing);
    expect(find.text('More details you want to share about patient (optional)'), findsNothing);
    expect(find.text('Feeding/Medicine Assistance (optional)'), findsOneWidget);

    // Pre-filled from the requirement.
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
    expect(find.text('74'), findsOneWidget);
    expect(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), findsOneWidget);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('28000'), findsOneWidget);
  });

  testWidgets('does not show Frequency & Salary before the requirement has ever been approved', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo, _requirement());

    expect(find.text('Frequency & Salary'), findsNothing);
  });

  testWidgets('saving edits calls editRequirement without mobility or description', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pumpTall(tester, repo, _requirement(frequencyOfCare: 'daily', salaryAmount: 28000));

    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '80');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editCalled, isTrue);
    expect(repo.capturedCareReceiver!.age, 80);
    final sentBody = repo.capturedCareReceiver!.toJson();
    expect(sentBody.containsKey('mobility'), isFalse);
    expect(repo.capturedFrequencyOfCare, 'daily');
    expect(repo.capturedSalaryAmount, 28000);
  });

  testWidgets('shows a server error message when saving fails', (tester) async {
    final repo = _FakeIndividualRepository(
      editError: ApiException(message: 'Something went wrong', code: 'JOB_014'),
    );
    await _pumpTall(tester, repo, _requirement(frequencyOfCare: 'daily', salaryAmount: 28000));

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });
}
