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

JobModel _job({
  String status = 'active',
  int? salaryAmount = 30000,
  String? frequencyOfCare = 'daily',
  String? postedByRole,
  String? postedByName,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-08-10',
    'languages': ['hindi'],
    'salary_amount': salaryAmount,
    'preferred_gender': 'female',
    'status': status,
    'posted_by': 'admin-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (postedByRole != null) 'posted_by_role': postedByRole,
    if (postedByName != null) 'posted_by_name': postedByName,
  });
}

/// Full job detail — as returned by `GET /admin/jobs/:id` — with a nested
/// care_receiver, used for the Edit dialog's pre-fill / "view full details".
JobModel _jobWithCareReceiver({String status = 'active'}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-08-10',
    'languages': ['hindi'],
    'salary_amount': 30000,
    'preferred_gender': 'female',
    'status': status,
    'posted_by': 'admin-1',
    'posted_at': '2026-08-01T10:00:00Z',
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
      'toilet_assistance': ['others'],
      'toilet_assistance_other': 'Needs help with a raised commode seat',
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    },
  });
}

JobApplicationModel _application({
  String status = 'applied',
  String id = 'app-1',
  String? appliedAt = '2026-08-01T10:00:00Z',
  String? acceptedAt,
  String? rejectedAt,
  String? decidedByName,
}) {
  return JobApplicationModel.fromJson({
    'id': id,
    'job_id': 'job-1',
    'profile_id': 'profile-1',
    'status': status,
    'full_name': 'Ramesh Kumar',
    'phone': '+919876543210',
    'applied_at': appliedAt,
    'accepted_at': acceptedAt,
    'rejected_at': rejectedAt,
    'decided_by_name': decidedByName,
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

/// Mirrors admin_jobs_screen.dart's private `_formatDateTime` — kept in the
/// test rather than exported, so this also verifies the app's actual format
/// stays what the test expects (timezone-safe: same `.toLocal()` step).
String _expectedDateTime(String isoUtc) {
  final d = DateTime.parse(isoUtc).toLocal();
  final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '$date ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _FakeAdminJobsRepository extends AdminJobsRepository {
  List<JobModel> jobs;
  List<JobApplicationModel> applications;
  List<JobPosterOption> posters;
  bool createCalled = false;
  bool closeCalled = false;
  String? remindedJobId;
  String? decidedApplicationId;
  String? decidedStatus;
  String? updatedJobId;
  String? updatedDescription;
  CareReceiverInput? submittedCareReceiver;
  JobListFilters? lastListFilters;
  String? rejectedJobId;
  String? rejectedReason;

  _FakeAdminJobsRepository(this.jobs, {this.applications = const [], this.posters = const []}) : super(Dio());

  @override
  Future<List<JobModel>> list({JobListFilters filters = const JobListFilters()}) async {
    lastListFilters = filters;
    return jobs;
  }

  @override
  Future<List<JobPosterOption>> listPosters() async => posters;

  @override
  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async {
    return (_jobWithCareReceiver(status: jobs.first.status), applications);
  }

  @override
  Future<void> create({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    String? description,
    required String dutyType,
    required String frequencyOfCare,
    String? startDate,
    required List<String> languages,
    required int salaryAmount,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    createCalled = true;
    submittedCareReceiver = careReceiver;
    jobs = [...jobs, _job()];
  }

  @override
  Future<void> update(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    String? description,
    required String dutyType,
    required String frequencyOfCare,
    String? startDate,
    required List<String> languages,
    required int salaryAmount,
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
  Future<void> reject(String jobId, String reason) async {
    rejectedJobId = jobId;
    rejectedReason = reason;
    jobs = jobs.map((j) => _job(status: 'closed')).toList();
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

// The filter panel's dropdowns are DropdownButtonFormField<String?> (nullable
// — "All X"/"Any X" is represented as a null selection), a different runtime
// type from the create/edit form's DropdownButtonFormField<String> above, so
// they need their own finder.
Future<void> _selectFilterDropdown(WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field = find.widgetWithText(DropdownButtonFormField<String?>, fieldLabel).first;
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

const _descriptionLabel = 'More details you want to share about patient';

/// Picks today's date (the picker's default) for the mandatory Preferred
/// Start Date field via its own OK button.
Future<void> _pickPreferredStartDate(WidgetTester tester) async {
  final dateButton = find.widgetWithText(OutlinedButton, 'Select date');
  await tester.ensureVisible(dateButton);
  await tester.tap(dateButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Fills every required field up through (and including) Toilet Assistance —
/// i.e. everything needed before Duty/Language/Description — so individual
/// tests can pick up from there.
Future<void> _fillAboutPatientRequiredFields(WidgetTester tester) async {
  await _selectDropdown(tester, 'City (Mandatory)', 'Bangalore');

  final area = find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)');
  await tester.ensureVisible(area);
  await tester.enterText(area, 'Indiranagar');
  await tester.pumpAndSettle();

  final age = find.widgetWithText(TextField, "Patient's Age (Mandatory)");
  await tester.ensureVisible(age);
  await tester.enterText(age, '72');
  await tester.pumpAndSettle();

  await _selectDropdown(tester, "Patient's Gender (Mandatory)", 'Female');

  final weight = find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
  await tester.ensureVisible(weight);
  await tester.enterText(weight, '58');
  await tester.pumpAndSettle();

  await _selectDropdown(tester, 'Mobility', 'Walks independently');
  await _selectDropdown(tester, 'Communication', 'Can Speak/Communicate');
  await _selectDropdown(tester, 'Feeding', 'Oral feeding – independent');
  await _tapChip(tester, 'Others');
}

Future<void> _fillSalary(WidgetTester tester, {String amount = '30000'}) async {
  final salary = find.widgetWithText(TextField, 'Salary (₹/month) (Mandatory)');
  await tester.ensureVisible(salary);
  await tester.enterText(salary, amount);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists posted jobs with job number, duty type, city, salary, and status', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('24Hrs - Live In · Bangalore'), findsOneWidget);
    // Fixture's frequency_of_care is 'daily' — the unit follows it.
    expect(find.text('₹30000/day'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('shows no jobs posted yet with no filters active, vs no jobs match these filters once one is',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    expect(find.text('No jobs posted yet.'), findsOneWidget);
    expect(find.text('No jobs match these filters.'), findsNothing);

    await _selectFilterDropdown(tester, 'City', 'Bangalore');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
    await tester.pumpAndSettle();

    expect(find.text('No jobs posted yet.'), findsNothing);
    expect(find.text('No jobs match these filters.'), findsOneWidget);
  });

  testWidgets('Job Poster filter options come from listPosters(), shown as name (phone)', (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job()],
      posters: const [
        JobPosterOption(id: 'admin-1', fullName: 'Admin One', phone: '+919876500000'),
        JobPosterOption(id: 'admin-2', fullName: 'Priya Admin', phone: '+919876500001'),
      ],
    );
    await _pump(tester, repo);

    final posterField = find.widgetWithText(DropdownButtonFormField<String?>, 'Job Poster').first;
    await tester.tap(posterField);
    await tester.pumpAndSettle();

    expect(find.text('Admin One (+919876500000)'), findsOneWidget);
    expect(find.text('Priya Admin (+919876500001)'), findsOneWidget);
  });

  testWidgets(
      'selecting Job Poster/City/Patient Gender/Duty Time/Status/Language and tapping Apply Filters '
      'calls list() with all of them', (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job()],
      posters: const [JobPosterOption(id: 'admin-1', fullName: 'Admin One', phone: '+919876500000')],
    );
    await _pump(tester, repo);

    await _selectFilterDropdown(tester, 'Job Poster', 'Admin One (+919876500000)');
    await _selectFilterDropdown(tester, 'City', 'Bangalore');
    await _selectFilterDropdown(tester, "Patient's Gender", 'Female');
    await _selectFilterDropdown(tester, 'Duty Time', '24Hrs - Live In');
    await _selectFilterDropdown(tester, 'Status', 'Closed');
    await _selectFilterDropdown(tester, 'Language', 'Hindi');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
    await tester.pumpAndSettle();

    expect(
      repo.lastListFilters,
      isA<JobListFilters>()
          .having((f) => f.postedBy, 'postedBy', 'admin-1')
          .having((f) => f.city, 'city', 'bangalore')
          .having((f) => f.gender, 'gender', 'female')
          .having((f) => f.dutyType, 'dutyType', 'live_in')
          .having((f) => f.status, 'status', 'closed')
          .having((f) => f.language, 'language', 'hindi'),
    );
  });

  testWidgets('shows the salary unit as /month on the job row for a monthly job', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(frequencyOfCare: 'monthly')]);
    await _pump(tester, repo);

    expect(find.text('₹30000/month'), findsOneWidget);
  });

  testWidgets(
      "the Salary field's unit label follows Frequency of Care as it's picked, and the posted job's row "
      'matches whichever was selected', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    // Before any Frequency of Care is picked, the label defaults to /month.
    expect(find.text('Salary (₹/month) (Mandatory)'), findsOneWidget);

    await _fillAboutPatientRequiredFields(tester);
    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');

    expect(find.text('Salary (₹/day) (Mandatory)'), findsOneWidget);
    expect(find.text('Salary (₹/month) (Mandatory)'), findsNothing);

    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Monthly');

    expect(find.text('Salary (₹/month) (Mandatory)'), findsOneWidget);
    expect(find.text('Salary (₹/day) (Mandatory)'), findsNothing);

    await _pickPreferredStartDate(tester);
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

  testWidgets('flags a job with no salary set instead of silently showing nothing', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(salaryAmount: null)]);
    await _pump(tester, repo);

    expect(find.text('Salary not set'), findsOneWidget);
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

  testWidgets('shows a Pending Review badge and Reject button for a pending_review job, but not an active one',
      (tester) async {
    final repo = _FakeAdminJobsRepository([
      _job(status: 'pending_review', salaryAmount: null, frequencyOfCare: null),
      _job(status: 'active'),
    ]);
    await _pump(tester, repo);

    expect(find.text('Pending Review'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets('shows who posted a NurseNow individual requirement, but not an admin-posted job', (tester) async {
    final repo = _FakeAdminJobsRepository([
      _job(
        status: 'pending_review',
        salaryAmount: null,
        frequencyOfCare: null,
        postedByRole: 'individual',
        postedByName: 'Asha Patel',
      ),
      _job(status: 'active', postedByRole: 'admin'),
    ]);
    await _pump(tester, repo);

    expect(find.text('Posted by patient/family — Asha Patel'), findsOneWidget);
  });

  testWidgets('tapping Reject opens a reason dialog and calls the repository', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject requirement'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Does not meet our coverage area');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.rejectedJobId, 'job-1');
    expect(repo.rejectedReason, 'Does not meet our coverage area');
  });

  testWidgets('Post New Job opens a dialog; filling required fields and submitting calls create()',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(find.text('Post New Job'), findsWidgets); // button label + dialog title
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('About Patient Condition'), findsNothing);
    expect(find.text('Medicine'), findsOneWidget);
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);

    await _fillAboutPatientRequiredFields(tester);
    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
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

  testWidgets('Preferred Start Date heading stays visible after a date is picked', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred Start Date (Mandatory)'), findsOneWidget);
    expect(find.text('Select date'), findsOneWidget);

    final dateButton = find.widgetWithText(OutlinedButton, 'Select date');
    await tester.ensureVisible(dateButton);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();

    // Confirm the date picker's default (today's) date via its own OK button.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The heading is still there — before this fix, the button's own label
    // doubled as both the heading and the value, so picking a date replaced
    // "Preferred Start Date" with a bare, context-free date.
    expect(find.text('Preferred Start Date (Mandatory)'), findsOneWidget);
    expect(find.text('Select date'), findsNothing);
  });

  testWidgets(
      'tapping outside the Post New Job dialog does not dismiss it or lose the partially-filled data',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    final age = find.widgetWithText(TextField, "Patient's Age (Mandatory)");
    await tester.ensureVisible(age);
    await tester.enterText(age, '72');
    await tester.pumpAndSettle();

    // Tap the modal barrier, well outside the dialog's bounds.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Still open, and the typed value is still there — a stray outside
    // click must not silently discard in-progress form data.
    expect(find.text('Post New Job'), findsWidgets);
    expect(find.text('72'), findsOneWidget);
    expect(repo.createCalled, isFalse);
  });

  testWidgets(
      'only age/weight/gender/city/area/start-date are hard-required — mobility, communication, feeding, '
      'toilet assistance, medical assistance, and description can all be left unselected/empty', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'City (Mandatory)', 'Bangalore');

    final area = find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)');
    await tester.ensureVisible(area);
    await tester.enterText(area, 'Indiranagar');
    await tester.pumpAndSettle();

    final age = find.widgetWithText(TextField, "Patient's Age (Mandatory)");
    await tester.ensureVisible(age);
    await tester.enterText(age, '72');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, "Patient's Gender (Mandatory)", 'Female');

    final weight = find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '58');
    await tester.pumpAndSettle();

    // Deliberately skip Mobility, Communication, Feeding, Toilet Assistance,
    // and Medical Assistance — none of them should block submission.
    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
    await _tapChip(tester, 'Hindi');

    // Deliberately leave the description empty too — it's optional now.
    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue,
        reason: 'mobility/communication/feeding/toilet assistance/medical assistance/description are optional now');
  });

  testWidgets('Post is always clickable; tapping it with every mandatory field empty highlights all of them '
      'in red and does not submit', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    expect(tester.widget<ElevatedButton>(postButton).onPressed, isNotNull, reason: 'Post must never be disabled');
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isFalse);
    // Every still-empty mandatory field shows its own error simultaneously
    // — not just the first one. (Area itself isn't even rendered yet since
    // it only appears once a city is picked — covered separately below.)
    expect(find.text('Please select a city'), findsOneWidget);
    expect(find.text('Age is required (1-120)'), findsOneWidget);
    expect(find.text('Please select a gender'), findsOneWidget);
    expect(find.text('Weight is required (1-300 kg)'), findsOneWidget);
    expect(find.text('Salary is required'), findsOneWidget);
    expect(find.text('Please select duty hours'), findsOneWidget);
    expect(find.text('Please select a frequency'), findsOneWidget);
    expect(find.text('Please select a start date'), findsOneWidget);
    expect(find.text('Select at least one language'), findsOneWidget);
  });

  testWidgets('tapping Post with only Area missing does not submit and moves the cursor into Area',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'City (Mandatory)', 'Bangalore');
    // Area deliberately left blank.

    final age = find.widgetWithText(TextField, "Patient's Age (Mandatory)");
    await tester.ensureVisible(age);
    await tester.enterText(age, '72');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, "Patient's Gender (Mandatory)", 'Female');

    final weight = find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '58');
    await tester.pumpAndSettle();

    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isFalse);
    expect(find.text('Area is required'), findsOneWidget);
    // Area is the only thing missing, so it's the one that gets focused —
    // the literal cursor-to-first-invalid behavior.
    final areaField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)'));
    expect(areaField.focusNode!.hasFocus, isTrue);
  });

  testWidgets('vital monitoring toggle reveals a required multi-select that blocks submit until answered',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillAboutPatientRequiredFields(tester);
    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    final vitalsSwitch = find.text('Is regular vital monitoring required?');
    await tester.ensureVisible(vitalsSwitch);
    await tester.tap(vitalsSwitch);
    await tester.pumpAndSettle();

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isFalse, reason: 'vitals on but no monitoring type selected yet');
    expect(find.text('Select at least one vital to monitor'), findsOneWidget);

    await _tapChip(tester, 'Blood pressure');
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
  });

  testWidgets('selecting Tube feeding does not reveal any extra question — the dropdown alone is enough',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'City (Mandatory)', 'Bangalore');

    final area = find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)');
    await tester.ensureVisible(area);
    await tester.enterText(area, 'Indiranagar');
    await tester.pumpAndSettle();

    final age = find.widgetWithText(TextField, "Patient's Age (Mandatory)");
    await tester.ensureVisible(age);
    await tester.enterText(age, '72');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, "Patient's Gender (Mandatory)", 'Female');

    final weight = find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '58');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'Mobility', 'Walks independently');
    await _selectDropdown(tester, 'Communication', 'Can Speak/Communicate');
    await _selectDropdown(tester, 'Feeding', 'Tube feeding');
    await _tapChip(tester, 'Others');
    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
    await _tapChip(tester, 'Hindi');

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    expect(find.text('Needs caregiver assistance with tube feeding'), findsNothing);

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue, reason: 'the feeding dropdown alone is enough, no extra field required');
  });

  testWidgets(
      'selecting Others for Toilet Assistance reveals a free-text field whose value is submitted '
      'alongside the selected values', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(find.text('Please describe the other toilet assistance'), findsNothing);

    await _fillAboutPatientRequiredFields(tester); // taps the "Others" toilet assistance chip

    final otherField = find.widgetWithText(TextField, 'Please describe the other toilet assistance');
    expect(otherField, findsOneWidget);
    await tester.ensureVisible(otherField);
    await tester.enterText(otherField, 'Needs help with a raised commode seat');
    await tester.pumpAndSettle();

    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
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
    expect(repo.submittedCareReceiver!.toiletAssistance, contains(ToiletAssistance.others));
    expect(repo.submittedCareReceiver!.toiletAssistanceOther, 'Needs help with a raised commode seat');
  });

  testWidgets(
      'unselecting Others for Toilet Assistance hides the free-text field and it is not submitted',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillAboutPatientRequiredFields(tester); // taps the "Others" toilet assistance chip
    await tester.enterText(
      find.widgetWithText(TextField, 'Please describe the other toilet assistance'),
      'Some detail',
    );
    await tester.pumpAndSettle();

    await _tapChip(tester, 'Others'); // untap it
    expect(find.text('Please describe the other toilet assistance'), findsNothing);

    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
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
    expect(repo.submittedCareReceiver!.toiletAssistance, isNot(contains(ToiletAssistance.others)));
    expect(repo.submittedCareReceiver!.toiletAssistanceOther, isNull);
  });

  testWidgets(
      'selecting Other for medical Condition(s) reveals a free-text field whose value is submitted '
      'alongside the selected conditions', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillAboutPatientRequiredFields(tester);

    final medicalConditionSwitch = find.text('Has a medical condition the caregiver should know about?');
    await tester.ensureVisible(medicalConditionSwitch);
    await tester.tap(medicalConditionSwitch);
    await tester.pumpAndSettle();

    expect(find.text('Please describe the other condition'), findsNothing);

    await _tapChip(tester, 'Other');

    final otherField = find.widgetWithText(TextField, 'Please describe the other condition');
    expect(otherField, findsOneWidget);
    await tester.ensureVisible(otherField);
    await tester.enterText(otherField, 'Recovering from hip surgery');
    await tester.pumpAndSettle();

    await _fillSalary(tester);
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)', '12Hrs Day Shift (8am to 8pm)');
    await _selectDropdown(tester, 'Frequency of Care (Mandatory)', 'Daily');
    await _pickPreferredStartDate(tester);
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
    expect(repo.submittedCareReceiver!.medicalConditions, contains(MedicalCondition.other));
    expect(repo.submittedCareReceiver!.medicalConditionOther, 'Recovering from hip surgery');
  });

  testWidgets('Edit opens the form pre-filled with the job\'s full details', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Job #42'), findsOneWidget);
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
    expect(find.text('72'), findsOneWidget, reason: 'age should be pre-filled from the care receiver');
    expect(find.text('58'), findsOneWidget, reason: 'weight should be pre-filled from the care receiver');
    // Edit fixture's frequency_of_care is 'daily' — the label's unit follows it.
    expect(
      find.widgetWithText(TextField, 'Salary (₹/day) (Mandatory)'),
      findsOneWidget,
    );
    final salaryField = tester.widget<TextField>(find.widgetWithText(TextField, 'Salary (₹/day) (Mandatory)'));
    expect(salaryField.controller!.text, '30000', reason: 'salary should be pre-filled from the job');
    expect(
      find.widgetWithText(TextField, _descriptionLabel),
      findsOneWidget,
      reason: 'description field should be pre-filled with the existing job description',
    );
    final description = tester.widget<TextField>(find.widgetWithText(TextField, _descriptionLabel));
    expect(description.controller!.text, 'Need a caregiver');
  });

  testWidgets(
      'Edit pre-fills the toilet-assistance "Others" free-text field from the existing care receiver',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final otherField = find.widgetWithText(TextField, 'Please describe the other toilet assistance');
    expect(otherField, findsOneWidget);
    expect(
      tester.widget<TextField>(otherField).controller!.text,
      'Needs help with a raised commode seat',
    );
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

  testWidgets('tapping outside the Edit dialog does not dismiss it or lose the in-progress edit', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final description = find.widgetWithText(TextField, _descriptionLabel);
    await tester.ensureVisible(description);
    await tester.enterText(description, 'Updated details for the caregiver');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Edit Job #42'), findsOneWidget);
    final descriptionField = tester.widget<TextField>(find.widgetWithText(TextField, _descriptionLabel));
    expect(descriptionField.controller!.text, 'Updated details for the caregiver');
    expect(repo.updatedJobId, isNull);
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

  testWidgets('Applicants dialog shows when the applicant applied, was accepted, and who accepted them',
      (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job(status: 'closed')],
      applications: [
        _application(
          status: 'accepted',
          appliedAt: '2026-08-01T10:00:00Z',
          acceptedAt: '2026-08-02T11:30:00Z',
          decidedByName: 'Priya Admin',
        ),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Applied: ${_expectedDateTime('2026-08-01T10:00:00Z')}'), findsOneWidget);
    expect(
      find.text('Accepted: ${_expectedDateTime('2026-08-02T11:30:00Z')} by Priya Admin'),
      findsOneWidget,
    );
  });

  testWidgets('Applicants dialog shows who declined a previously-accepted applicant, and when', (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job()],
      applications: [
        _application(
          status: 'rejected',
          appliedAt: '2026-08-01T10:00:00Z',
          acceptedAt: '2026-08-02T11:30:00Z',
          rejectedAt: '2026-08-03T09:15:00Z',
          decidedByName: 'Priya Admin',
        ),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(
      find.text('Declined by Priya Admin: ${_expectedDateTime('2026-08-03T09:15:00Z')}'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the job row opens a read-only detail view, not the editable form', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Job #42'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('About Patient')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Hours Care Needed')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.widgetWithText(ElevatedButton, 'Edit')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Close')), findsOneWidget);
    // Read-only: no editable form fields, no Save Changes button, no
    // "Edit Job #42" dialog title (that's the editable form's title).
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsNothing);
    expect(find.text('Edit Job #42'), findsNothing);
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsNothing);
  });

  testWidgets('tapping Edit inside the read-only detail view opens the editable form', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Job #42'));
    await tester.pumpAndSettle();

    final readOnlyDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: readOnlyDialog, matching: find.widgetWithText(ElevatedButton, 'Edit')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Job #42'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    // Exactly one dialog on screen — the read-only one was popped first,
    // not left stacked underneath the editable form.
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
