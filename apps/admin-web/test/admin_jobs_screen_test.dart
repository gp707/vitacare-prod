import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/jobs/data/admin_jobs_repository.dart';
import 'package:admin_web/features/jobs/screens/admin_jobs_screen.dart';

JobModel _job({String status = 'active'}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'languages': ['hindi'],
    'preferred_gender': 'female',
    'status': status,
    'posted_by': 'admin-1',
    'created_at': '2026-08-01T10:00:00Z',
  });
}

/// Full job detail — as returned by `GET /admin/jobs/:id` — with a nested
/// care_receiver, used for the Edit dialog's pre-fill / "view full details".
JobModel _jobWithCareReceiver({String status = 'active'}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'languages': ['hindi'],
    'preferred_gender': 'female',
    'status': status,
    'posted_by': 'admin-1',
    'created_at': '2026-08-01T10:00:00Z',
    'care_receiver': {
      'id': 'cr-1',
      'age': 72,
      'gender': 'female',
      'weight_kg': 58,
      'mobility': 'walks_independently',
      'communication': 'verbal',
      'feeding_type': 'oral_independent',
      'medical_assistance': [],
      'has_medical_condition': false,
      'medical_conditions': [],
      'toilet_assistance': 'none',
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    },
  });
}

JobApplicationModel _application({String status = 'applied', String id = 'app-1'}) {
  return JobApplicationModel.fromJson({
    'id': id,
    'job_id': 'job-1',
    'profile_id': 'profile-1',
    'status': status,
    'full_name': 'Ramesh Kumar',
    'phone': '+919876543210',
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeAdminJobsRepository extends AdminJobsRepository {
  List<JobModel> jobs;
  List<JobApplicationModel> applications;
  bool createCalled = false;
  bool closeCalled = false;
  String? remindedJobId;
  String? decidedApplicationId;
  String? decidedStatus;
  String? updatedJobId;
  String? updatedDescription;

  _FakeAdminJobsRepository(this.jobs, {this.applications = const []}) : super(Dio());

  @override
  Future<List<JobModel>> list({String? status}) async => jobs;

  @override
  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async {
    return (_jobWithCareReceiver(status: jobs.first.status), applications);
  }

  @override
  Future<void> create({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    createCalled = true;
    jobs = [...jobs, _job()];
  }

  @override
  Future<void> update(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    updatedJobId = jobId;
    updatedDescription = description;
  }

  @override
  Future<void> close(String jobId) async {
    closeCalled = true;
    jobs = jobs.map((j) => _job(status: 'closed')).toList();
  }

  @override
  Future<void> remind(String jobId) async {
    remindedJobId = jobId;
  }

  @override
  Future<void> decideApplication(String jobId, String applicationId, String status) async {
    decidedApplicationId = applicationId;
    decidedStatus = status;
    applications = applications
        .map((a) => a.id == applicationId ? _application(status: status, id: a.id) : a)
        .toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminJobsRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        adminJobsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AdminJobsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDropdown(WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, fieldLabel).first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String chipLabel) async {
  final chip = find.widgetWithText(FilterChip, chipLabel);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

const _descriptionLabel =
    'More details you want to share about patient or requirement which can help caregiver to decide';

/// Fills every required field up through (and including) Toilet Assistance —
/// i.e. everything needed before Duty/Language/Description — so individual
/// tests can pick up from there.
Future<void> _fillAboutPatientRequiredFields(WidgetTester tester) async {
  await _selectDropdown(tester, 'City', 'Bangalore');

  final age = find.widgetWithText(TextField, "Patient's Age");
  await tester.ensureVisible(age);
  await tester.enterText(age, '72');
  await tester.pumpAndSettle();

  await _selectDropdown(tester, "Patient's Gender", 'Female');

  final weight = find.widgetWithText(TextField, "Patient's Weight (kg)");
  await tester.ensureVisible(weight);
  await tester.enterText(weight, '58');
  await tester.pumpAndSettle();

  await _selectDropdown(tester, 'Mobility', 'Walks independently');
  await _selectDropdown(tester, 'Communication', 'Speaks / communicates verbally');
  await _selectDropdown(tester, 'Feeding', 'Oral feeding – independent');
  await _selectDropdown(tester, 'Toilet Assistance', 'None');
}

void main() {
  testWidgets('lists posted jobs with duty type, city, and status', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    expect(find.text('24Hrs - Live In · Bangalore'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
  });

  testWidgets('shows Close for an active job but not a closed one', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
  });

  testWidgets('shows Remind for an active job but not a closed one', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Remind'), findsOneWidget);
  });

  testWidgets('tapping Close calls the repository and refreshes', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(repo.closeCalled, isTrue);
  });

  testWidgets('tapping Remind calls the repository with the job id', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Remind'));
    await tester.pumpAndSettle();

    expect(repo.remindedJobId, 'job-1');
  });

  testWidgets('Post New Job opens a dialog; filling required fields and submitting calls create()',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(find.text('Post New Job'), findsWidgets); // button label + dialog title
    expect(find.text('About Patient'), findsOneWidget);

    await _fillAboutPatientRequiredFields(tester);
    await _selectDropdown(tester, 'Duty Type', '12Hrs Day Shift (8am to 8pm)');
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
  });

  testWidgets('vital monitoring toggle reveals a required multi-select that blocks submit until answered',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillAboutPatientRequiredFields(tester);
    await _selectDropdown(tester, 'Duty Type', '12Hrs Day Shift (8am to 8pm)');
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    final postButtonBefore = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post'));
    expect(postButtonBefore.onPressed, isNotNull, reason: 'vitals off — required fields already satisfied');

    final vitalsSwitch = find.text('Is regular vital monitoring required?');
    await tester.ensureVisible(vitalsSwitch);
    await tester.tap(vitalsSwitch);
    await tester.pumpAndSettle();

    final postButtonVitalsOn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post'));
    expect(postButtonVitalsOn.onPressed, isNull, reason: 'vitals on but no monitoring type selected yet');

    await _tapChip(tester, 'Blood pressure');

    final postButtonAfter = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post'));
    expect(postButtonAfter.onPressed, isNotNull);
  });

  testWidgets('tube feeding reveals a required assistance checkbox that blocks submit until answered',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'City', 'Bangalore');

    final age = find.widgetWithText(TextField, "Patient's Age");
    await tester.ensureVisible(age);
    await tester.enterText(age, '72');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, "Patient's Gender", 'Female');

    final weight = find.widgetWithText(TextField, "Patient's Weight (kg)");
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '58');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'Mobility', 'Walks independently');
    await _selectDropdown(tester, 'Communication', 'Speaks / communicates verbally');
    await _selectDropdown(tester, 'Feeding', 'Tube feeding');
    await _selectDropdown(tester, 'Toilet Assistance', 'None');
    await _selectDropdown(tester, 'Duty Type', '12Hrs Day Shift (8am to 8pm)');
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    expect(
      find.text('Needs caregiver assistance with tube feeding'),
      findsOneWidget,
      reason: 'tube feeding should reveal the conditional assistance question',
    );

    final postButtonBefore = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post'));
    expect(postButtonBefore.onPressed, isNull);

    final checkbox = find.text('Needs caregiver assistance with tube feeding');
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    final postButtonAfter = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post'));
    expect(postButtonAfter.onPressed, isNotNull);
  });

  testWidgets('Edit opens the form pre-filled with the job\'s full details', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Job'), findsOneWidget);
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    expect(find.widgetWithText(TextField, "Patient's Age"), findsOneWidget);
    expect(find.text('72'), findsOneWidget, reason: 'age should be pre-filled from the care receiver');
    expect(find.text('58'), findsOneWidget, reason: 'weight should be pre-filled from the care receiver');
    expect(
      find.widgetWithText(TextField, _descriptionLabel),
      findsOneWidget,
      reason: 'description field should be pre-filled with the existing job description',
    );
    final description = tester.widget<TextField>(find.widgetWithText(TextField, _descriptionLabel));
    expect(description.controller!.text, 'Need a caregiver');
  });

  testWidgets('editing and saving calls repository.update() with the job id, not create()', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Updated details for the caregiver');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.updatedJobId, 'job-1');
    expect(repo.updatedDescription, 'Updated details for the caregiver');
    expect(repo.createCalled, isFalse);
  });

  testWidgets('Applicants dialog shows Accept/Reject for an applied application; Accept calls decideApplication',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()], applications: [_application(status: 'applied')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Kumar — applied'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('Applicants dialog shows only Reject for an already-accepted application', (tester) async {
    final repo =
        _FakeAdminJobsRepository([_job(status: 'closed')], applications: [_application(status: 'accepted')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Kumar — accepted'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });
}
