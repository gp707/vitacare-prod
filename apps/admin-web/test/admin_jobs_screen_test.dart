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
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/rate_card/data/rate_card_repository.dart';
import 'package:admin_web/features/scope_of_work/data/scope_of_work_repository.dart';

class _FakeRateCardRepository extends RateCardRepository {
  final List<RateCardWithUpdater>? result;
  final Object? error;

  _FakeRateCardRepository({this.result, this.error}) : super(Dio());

  @override
  Future<List<RateCardWithUpdater>> get() async {
    if (error != null) throw error!;
    return result!;
  }
}

RateCardWithUpdater _rateCardWithUpdater({
  required String frequencyOfCare,
  required String companion,
  String bedside = 'BEDSIDE_RATE',
  String critical = 'CRITICAL_RATE',
}) =>
    RateCardWithUpdater(
      rateCard: RateCardModel(
        frequencyOfCare: frequencyOfCare,
        title: 'Salary Guidelines',
        columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
        rowLabels: const ['Care'],
        cells: [
          [companion, bedside, critical],
        ],
      ),
      updatedByName: null,
      updatedAt: '2026-08-30T10:00:00Z',
    );

final _scopeOfWork = ScopeOfWorkModel(
  companionCare: ['Emotional companionship', 'Meal assistance'],
  bedsideCare: ['Diaper changing & hygiene care'],
  criticalCare: ['Catheter care'],
);

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkWithUpdater> get() async => ScopeOfWorkWithUpdater(
        scopeOfWork: _scopeOfWork,
        updatedByName: null,
        updatedAt: '2026-08-30T10:00:00Z',
      );
}

/// A minimal organisation requirement fixture for the merged Jobs list —
/// full requirement-specific behavior (approve/reject/schedule/applicants)
/// is covered in admin_jobs_screen_requirements_test.dart.
AdminOrganisationRequirement _requirement({
  String id = 'r1',
  int requirementNumber = 101,
  String status = JobStatus.pendingReview,
  String postedAt = '2026-08-01T10:00:00Z',
}) {
  return AdminOrganisationRequirement(
    id: id,
    requirementNumber: requirementNumber,
    postedBy: 'org-user-1',
    typeOfNurse: TypeOfNurse.auxiliaryNurse,
    accommodationProvided: true,
    foodProvided: false,
    status: status,
    postedAt: postedAt,
    organisationName: 'City Rehab Center',
    organisationType: OrganisationType.rehab,
    city: City.bangalore,
    area: 'Whitefield',
  );
}

class _FakeAdminOrganisationRequirementsRepository
    extends AdminOrganisationRequirementsRepository {
  List<AdminOrganisationRequirement> items;
  int listCallCount = 0;
  OrganisationRequirementListFilters? lastFilters;

  _FakeAdminOrganisationRequirementsRepository([this.items = const []])
      : super(Dio());

  @override
  Future<List<AdminOrganisationRequirement>> list({
    OrganisationRequirementListFilters filters =
        const OrganisationRequirementListFilters(),
  }) async {
    listCallCount++;
    lastFilters = filters;
    return items;
  }
}

JobModel _job({
  String status = 'active',
  String? salaryAmount = '30000',
  String? frequencyOfCare = 'daily',
  String? postedByRole,
  String? postedByName,
  String postedAt = '2026-08-01T10:00:00Z',
  List<String> languages = const ['hindi'],
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'admin_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-08-10',
    'languages': languages,
    'salary_amount': salaryAmount,
    'preferred_gender': 'female',
    'status': status,
    'posted_by': 'admin-1',
    'posted_at': postedAt,
    'created_at': '2026-08-01T10:00:00Z',
    if (postedByRole != null) 'posted_by_role': postedByRole,
    if (postedByName != null) 'posted_by_name': postedByName,
  });
}

/// Full job detail — as returned by `GET /admin/jobs/:id` — with a nested
/// care_receiver, used for the Edit dialog's pre-fill / "view full details".
/// [careDuration] defaults to 'few_weeks' (derives to Daily) so most Edit
/// tests get a coherent Frequency of Care without each one having to pass it
/// explicitly — pass null to exercise a legacy job that predates the field.
JobModel _jobWithCareReceiver({
  String status = 'active',
  List<String> languages = const ['hindi'],
  String? careDuration = 'few_weeks',
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'admin_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-08-10',
    'care_duration': careDuration,
    'languages': languages,
    'salary_amount': '30000',
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
      'communication': 'verbal',
      'feeding_type': 'oral_feeding',
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
  String? declineReason,
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
    'decline_reason': declineReason,
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

/// Mirrors admin_jobs_screen.dart's private `_formatDateTime` — kept in the
/// test rather than exported, so this also verifies the app's actual format
/// stays what the test expects (timezone-safe: same `.toLocal()` step).
String _expectedDateTime(String isoUtc) {
  final d = DateTime.parse(isoUtc).toLocal();
  final date =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  return '$date $time';
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
  String? submittedFrequencyOfCare;
  String? submittedSalaryAmount;
  String? submittedCareDuration;
  CareReceiverInput? submittedCareReceiver;
  List<String>? submittedLanguages;
  JobListFilters? lastListFilters;
  int listCallCount = 0;
  String? rejectedJobId;
  String? rejectedReason;
  List<String> detailLanguages;
  String? detailCareDuration;

  _FakeAdminJobsRepository(this.jobs,
      {this.applications = const [],
      this.posters = const [],
      this.detailLanguages = const ['hindi'],
      this.detailCareDuration = 'few_weeks'})
      : super(Dio());

  @override
  Future<List<JobModel>> list(
      {JobListFilters filters = const JobListFilters()}) async {
    listCallCount++;
    lastListFilters = filters;
    return jobs;
  }

  @override
  Future<List<JobPosterOption>> listPosters() async => posters;

  @override
  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async {
    return (
      _jobWithCareReceiver(
        status: jobs.first.status,
        languages: detailLanguages,
        careDuration: detailCareDuration,
      ),
      applications
    );
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
    required String salaryAmount,
    String? preferredGender,
    String? preferredReligion,
    required String careDuration,
  }) async {
    createCalled = true;
    submittedCareReceiver = careReceiver;
    submittedLanguages = languages;
    submittedFrequencyOfCare = frequencyOfCare;
    submittedSalaryAmount = salaryAmount;
    submittedCareDuration = careDuration;
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
    required String salaryAmount,
    String? preferredGender,
    String? preferredReligion,
    required String careDuration,
  }) async {
    updatedJobId = jobId;
    submittedLanguages = languages;
    submittedFrequencyOfCare = frequencyOfCare;
    submittedSalaryAmount = salaryAmount;
    submittedCareReceiver = careReceiver;
    submittedCareDuration = careDuration;
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
  Future<void> decideApplication(
      String jobId, String applicationId, String status) async {
    decidedApplicationId = applicationId;
    decidedStatus = status;
    applications = applications
        .map((a) =>
            a.id == applicationId ? _application(status: status, id: a.id) : a)
        .toList();
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminJobsRepository repo, {
  _FakeAdminOrganisationRequirementsRepository? requirementsRepo,
  JobsScreenInitialFilter? initialFilter,
  List<RateCardWithUpdater>? rateCards,
  Object? rateCardError,
}) async {
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
            ..state =
                AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        adminJobsRepositoryProvider.overrideWithValue(repo),
        adminOrganisationRequirementsRepositoryProvider.overrideWithValue(
            requirementsRepo ?? _FakeAdminOrganisationRequirementsRepository()),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        rateCardRepositoryProvider.overrideWithValue(
          _FakeRateCardRepository(result: rateCards ?? const [], error: rateCardError),
        ),
      ],
      child: MaterialApp(home: AdminJobsScreen(initialFilter: initialFilter)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDropdown(
    WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field =
      find.widgetWithText(DropdownButtonFormField<String>, fieldLabel).first;
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
Future<void> _selectFilterDropdown(
    WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field =
      find.widgetWithText(DropdownButtonFormField<String?>, fieldLabel).first;
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

// Asserted absent in a few places — the field was removed from admin-web's
// form entirely (see CLAUDE.md's NurseNow section).
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

/// Fills Age/Gender/Weight/City/Area — the core Patient Details fields that
/// nearly every test needs, leaving Medical Condition at its "None" default
/// and Toilet Assistance/Feeding untouched (both optional).
Future<void> _fillPatientDetailsCore(WidgetTester tester) async {
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

  final weight =
      find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
  await tester.ensureVisible(weight);
  await tester.enterText(weight, '58');
  await tester.pumpAndSettle();
}

/// Finds the Salary field regardless of its current unit label (₹/day vs
/// ₹/month, which follows the derived Frequency of Care).
Future<void> _fillSalary(WidgetTester tester, {String amount = '30000'}) async {
  final salary = find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Salary'),
  );
  await tester.ensureVisible(salary);
  await tester.enterText(salary, amount);
  await tester.pumpAndSettle();
}

/// Fills every hard-required field on the unified form (Patient Details'
/// core fields + Hours Care Needed + Preferred Start Date + Duration Care is
/// Needed + Toilet Assistance + Feeding/Medicine Assistance + Salary),
/// leaving Medical Condition/Language Preference at their defaults — used by
/// tests that only care about getting to a submittable state.
Future<void> _fillMandatoryFields(WidgetTester tester) async {
  await _fillPatientDetailsCore(tester);
  await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
      '12Hrs Day Shift (8am to 8pm)');
  await _pickPreferredStartDate(tester);
  await _selectDropdown(
      tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
  await _selectDropdown(tester, 'Toilet Assistance (Mandatory)',
      'Independent/minimal support');
  await _selectDropdown(tester, 'Feeding/Medicine Assistance (Mandatory)',
      'Oral feeding');
  await _fillSalary(tester);
}

void main() {
  testWidgets(
      'lists posted jobs with job number, duty type, city, salary, and status',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('24Hrs - Live In · Bangalore'), findsOneWidget);
    // Fixture's frequency_of_care is 'daily' — the unit follows it.
    expect(find.text('₹30000/day'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets(
      'shows no jobs or requirements posted yet with no filters active, vs no match these filters once one is',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    expect(find.text('No jobs or requirements posted yet.'), findsOneWidget);
    expect(find.text('No jobs or requirements match these filters.'),
        findsNothing);

    await _selectFilterDropdown(tester, 'City', 'Bangalore');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
    await tester.pumpAndSettle();

    expect(find.text('No jobs or requirements posted yet.'), findsNothing);
    expect(find.text('No jobs or requirements match these filters.'),
        findsOneWidget);
  });

  testWidgets(
      'Job Poster filter options come from listPosters(), shown as name (phone)',
      (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job()],
      posters: const [
        JobPosterOption(
            id: 'admin-1', fullName: 'Admin One', phone: '+919876500000'),
        JobPosterOption(
            id: 'admin-2', fullName: 'Priya Admin', phone: '+919876500001'),
      ],
    );
    await _pump(tester, repo);

    final posterField = find
        .widgetWithText(DropdownButtonFormField<String?>, 'Job Poster')
        .first;
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
      posters: const [
        JobPosterOption(
            id: 'admin-1', fullName: 'Admin One', phone: '+919876500000')
      ],
    );
    await _pump(tester, repo);

    await _selectFilterDropdown(
        tester, 'Job Poster', 'Admin One (+919876500000)');
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

  testWidgets(
      'entering a search term and tapping Apply Filters calls list() with it',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(
          TextField, 'Search job ID or patient ID (e.g. PAT-501)'),
      'ADMIN-JOB-500',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
    await tester.pumpAndSettle();

    expect(
        repo.lastListFilters,
        isA<JobListFilters>()
            .having((f) => f.search, 'search', 'ADMIN-JOB-500'));
  });

  testWidgets(
      'entering a patient display id searches for all jobs that patient posted',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(
          TextField, 'Search job ID or patient ID (e.g. PAT-501)'),
      'PAT-501',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
    await tester.pumpAndSettle();

    expect(repo.lastListFilters,
        isA<JobListFilters>().having((f) => f.search, 'search', 'PAT-501'));
  });

  testWidgets(
      'shows the salary unit as /month on the job row for a monthly job',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job(frequencyOfCare: 'monthly')]);
    await _pump(tester, repo);

    expect(find.text('₹30000/month'), findsOneWidget);
  });

  testWidgets(
      "the Salary field's unit label follows the derived Frequency of Care as Duration Care is Needed is "
      "picked, and the posted job's row matches whichever was derived", (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    // Before any Duration Care is Needed is picked, the label defaults to
    // /month and Frequency of Care shows "-".
    expect(find.text('Salary (₹/month) (Mandatory)'), findsOneWidget);

    await _fillMandatoryFields(tester); // picks 'Need for Few Weeks' -> derives Daily

    expect(find.text('Salary (₹/day) (Mandatory)'), findsOneWidget);
    expect(find.text('Salary (₹/month) (Mandatory)'), findsNothing);
    expect(find.text('Daily'), findsOneWidget);

    await _selectDropdown(
        tester, 'Duration Care is Needed (Mandatory)', 'Need for Long Term');

    expect(find.text('Salary (₹/month) (Mandatory)'), findsOneWidget);
    expect(find.text('Salary (₹/day) (Mandatory)'), findsNothing);
    expect(find.text('Monthly'), findsOneWidget);

    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.submittedFrequencyOfCare, 'monthly');
    expect(repo.submittedCareDuration, 'long_term');
  });

  testWidgets(
      'flags a job with no salary set instead of silently showing nothing',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job(salaryAmount: null)]);
    await _pump(tester, repo);

    expect(find.text('Salary not set'), findsOneWidget);
  });

  testWidgets('shows Close for an active job but not a closed one',
      (tester) async {
    final repo = _FakeAdminJobsRepository(
        [_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
  });

  testWidgets('shows Remind for an active job but not a closed one',
      (tester) async {
    final repo = _FakeAdminJobsRepository(
        [_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Remind'), findsOneWidget);
  });

  testWidgets('tapping Close calls the repository and refreshes',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(repo.closeCalled, isTrue);
  });

  testWidgets('tapping Remind calls the repository with the job id',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Remind'));
    await tester.pumpAndSettle();

    expect(repo.remindedJobId, 'job-1');
  });

  testWidgets(
      'shows a Pending Review badge and Reject button for a pending_review job, but not an active one',
      (tester) async {
    final repo = _FakeAdminJobsRepository([
      _job(status: 'pending_review', salaryAmount: null, frequencyOfCare: null),
      _job(status: 'active'),
    ]);
    await _pump(tester, repo);

    expect(find.text('Pending Review'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets(
      'shows who posted a NurseNow individual requirement, but not an admin-posted job',
      (tester) async {
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

  testWidgets('tapping Reject opens a reason dialog and calls the repository',
      (tester) async {
    final repo = _FakeAdminJobsRepository([
      _job(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)
    ]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject requirement'), findsOneWidget);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Does not meet our coverage area',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.rejectedJobId, 'job-1');
    expect(repo.rejectedReason, 'Does not meet our coverage area');
  });

  testWidgets(
      'Language Preference defaults to No Preference and can never block submission — an untouched selection submits an empty array',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    // "No Preference" starts selected; deliberately never tap a real
    // language chip.
    await _fillMandatoryFields(tester);

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.submittedLanguages, isEmpty);
  });

  testWidgets(
      'tapping a real language after No Preference replaces it — mutual exclusivity, mirroring nursenow-app',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillMandatoryFields(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.submittedLanguages, ['hindi']);
  });

  testWidgets(
      "editing a job with no languages set pre-fills No Preference, and admin's own change is what gets submitted — same field, kept in sync with what the patient set",
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()], detailLanguages: const []);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final noPreferenceChip =
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'No Preference'));
    expect(noPreferenceChip.selected, isTrue);

    await _tapChip(tester, 'Hindi');

    final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.submittedLanguages, ['hindi']);
  });

  testWidgets(
      'the job row and read-only detail view both show "No Preference" explicitly when languages is empty — never a blank gap',
      (tester) async {
    await _pump(
      tester,
      _FakeAdminJobsRepository([_job(languages: const [])], detailLanguages: const []),
    );

    // Job row summary line joins area/languages into one Text — check via
    // textContaining rather than an exact match.
    expect(find.textContaining('No Preference'), findsOneWidget);

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    // Read-only detail dialog renders "Languages" as its own exact-text row.
    expect(find.text('No Preference'), findsOneWidget);
  });

  testWidgets(
      'Post New Job opens a dialog matching nursenow-app\'s own field set/order exactly; filling required '
      'fields and submitting calls create()', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(
        find.text('Post New Job'), findsWidgets); // button label + dialog title
    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    expect(find.text('Nurse Fee Guidance'), findsOneWidget);
    // Removed entirely, universally.
    expect(find.text('Communication'), findsNothing);
    expect(find.text('Is regular vital monitoring required?'), findsNothing);
    expect(find.text(_descriptionLabel), findsNothing);
    // Already-removed prior feature, unrelated to this change.
    expect(find.text('About Patient Condition'), findsNothing);
    expect(find.text('Medicine'), findsNothing);

    await _fillMandatoryFields(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
  });

  testWidgets(
      'Preferred Start Date heading stays visible after a date is picked',
      (tester) async {
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
      'only age/weight/gender/city/area/duty-hours/start-date/duration/salary are hard-required — '
      'feeding and toilet assistance can be left unselected', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    // Deliberately skip Feeding and Toilet Assistance — neither should
    // block submission.
    await _fillMandatoryFields(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue,
        reason: 'feeding/toilet assistance are optional');
  });

  testWidgets(
      'Post is always clickable; tapping it with every mandatory field empty highlights all of them '
      'in red and does not submit', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    expect(tester.widget<ElevatedButton>(postButton).onPressed, isNotNull,
        reason: 'Post must never be disabled');
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
    expect(find.text('Please select duty hours'), findsOneWidget);
    expect(find.text('Please select a start date'), findsOneWidget);
    expect(find.text('Please select how long care is needed'), findsOneWidget);
    expect(find.text('Salary is required'), findsOneWidget);
    // Frequency of Care can never be invalid — it's derived, not picked.
    // Language Preference can never be invalid — it defaults to "No
    // Preference" and stays that way until the admin picks a real one.
    // Medical Condition can never be invalid — it defaults to "None".
  });

  testWidgets(
      'tapping Post with only Area missing does not submit and moves the cursor into Area',
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

    final weight =
        find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)");
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '58');
    await tester.pumpAndSettle();

    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
        '12Hrs Day Shift (8am to 8pm)');
    await _pickPreferredStartDate(tester);
    await _selectDropdown(
        tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
    await _fillSalary(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isFalse);
    expect(find.text('Area is required'), findsOneWidget);
    // Area is the only thing missing, so it's the one that gets focused —
    // the literal cursor-to-first-invalid behavior.
    final areaField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)'));
    expect(areaField.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
      'selecting Tube feeding does not reveal any extra question — the dropdown alone is enough',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillPatientDetailsCore(tester);
    await _selectDropdown(
        tester, 'Feeding/Medicine Assistance (Mandatory)', 'Tube feeding');
    await _selectDropdown(
        tester, 'Toilet Assistance (Mandatory)', 'Others');

    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
        '12Hrs Day Shift (8am to 8pm)');
    await _pickPreferredStartDate(tester);
    await _selectDropdown(
        tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
    await _fillSalary(tester);
    await _tapChip(tester, 'Hindi');

    expect(find.text('Needs caregiver assistance with tube feeding'),
        findsNothing);

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue,
        reason:
            'the feeding dropdown alone is enough, no extra field required');
  });

  testWidgets(
      'selecting Others for Toilet Assistance reveals a free-text field whose value is submitted '
      'alongside the selected values', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(
        find.text('Please describe the other toilet assistance'), findsNothing);

    await _fillPatientDetailsCore(tester);
    await _selectDropdown(tester, 'Toilet Assistance (Mandatory)', 'Others');

    final otherField = find.widgetWithText(
        TextField, 'Please describe the other toilet assistance');
    expect(otherField, findsOneWidget);
    await tester.ensureVisible(otherField);
    await tester.enterText(otherField, 'Needs help with a raised commode seat');
    await tester.pumpAndSettle();

    await _selectDropdown(
        tester, 'Feeding/Medicine Assistance (Mandatory)', 'Oral feeding');
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
        '12Hrs Day Shift (8am to 8pm)');
    await _pickPreferredStartDate(tester);
    await _selectDropdown(
        tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
    await _fillSalary(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.submittedCareReceiver!.toiletAssistance,
        contains(ToiletAssistance.others));
    expect(repo.submittedCareReceiver!.toiletAssistanceOther,
        'Needs help with a raised commode seat');
  });

  testWidgets(
      'switching Toilet Assistance away from Others hides the free-text field and it is not submitted',
      (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    await _fillPatientDetailsCore(tester);
    await _selectDropdown(tester, 'Toilet Assistance (Mandatory)', 'Others');
    await tester.enterText(
      find.widgetWithText(
          TextField, 'Please describe the other toilet assistance'),
      'Some detail',
    );
    await tester.pumpAndSettle();

    // A single-select dropdown can only be changed to a different value, not
    // cleared back to "nothing selected" — the mandatory-field equivalent of
    // "unselecting".
    await _selectDropdown(tester, 'Toilet Assistance (Mandatory)',
        'Independent/minimal support');
    expect(
        find.text('Please describe the other toilet assistance'), findsNothing);

    await _selectDropdown(
        tester, 'Feeding/Medicine Assistance (Mandatory)', 'Oral feeding');
    await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
        '12Hrs Day Shift (8am to 8pm)');
    await _pickPreferredStartDate(tester);
    await _selectDropdown(
        tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
    await _fillSalary(tester);
    await _tapChip(tester, 'Hindi');

    final postButton = find.widgetWithText(ElevatedButton, 'Post');
    await tester.ensureVisible(postButton);
    await tester.tap(postButton);
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
    expect(repo.submittedCareReceiver!.toiletAssistance,
        isNot(contains(ToiletAssistance.others)));
    expect(repo.submittedCareReceiver!.toiletAssistanceOther, isNull);
  });

  group(
      'Medical Condition — always-visible mandatory multi-select with a "None" sentinel, mirroring '
      'nursenow-app\'s Post/Edit Requirement screens exactly', () {
    testWidgets(
        'defaults to None and can never block submission — an untouched selection submits has_medical_condition: false',
        (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      final noneChip =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'None'));
      expect(noneChip.selected, isTrue);

      await _fillMandatoryFields(tester);
      await _tapChip(tester, 'Hindi');

      final postButton = find.widgetWithText(ElevatedButton, 'Post');
      await tester.ensureVisible(postButton);
      await tester.tap(postButton);
      await tester.pumpAndSettle();

      expect(repo.createCalled, isTrue);
      expect(repo.submittedCareReceiver!.hasMedicalCondition, isFalse);
      expect(repo.submittedCareReceiver!.medicalConditions, isNull);
    });

    testWidgets('tapping a real condition after None replaces it — mutual exclusivity',
        (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      await _tapChip(tester, 'Diabetes');

      expect(
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'None')).selected,
          isFalse);
      expect(
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Diabetes')).selected,
          isTrue);
    });

    testWidgets('deselecting the only selected condition falls back to None',
        (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      await _tapChip(tester, 'Diabetes');
      await _tapChip(tester, 'Diabetes'); // deselect

      expect(
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'None')).selected,
          isTrue);
    });

    testWidgets(
        'selecting Other reveals a free-text field whose value is submitted alongside the selected conditions',
        (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      await _fillPatientDetailsCore(tester);

      expect(find.text('Please describe the other condition'), findsNothing);

      await _tapChip(tester, 'Other');

      final otherField =
          find.widgetWithText(TextField, 'Please describe the other condition');
      expect(otherField, findsOneWidget);
      await tester.ensureVisible(otherField);
      await tester.enterText(otherField, 'Recovering from hip surgery');
      await tester.pumpAndSettle();

      await _selectDropdown(
          tester, 'Toilet Assistance (Mandatory)', 'Independent/minimal support');
      await _selectDropdown(
          tester, 'Feeding/Medicine Assistance (Mandatory)', 'Oral feeding');
      await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
          '12Hrs Day Shift (8am to 8pm)');
      await _pickPreferredStartDate(tester);
      await _selectDropdown(
          tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');
      await _fillSalary(tester);
      await _tapChip(tester, 'Hindi');

      final postButton = find.widgetWithText(ElevatedButton, 'Post');
      await tester.ensureVisible(postButton);
      await tester.tap(postButton);
      await tester.pumpAndSettle();

      expect(repo.createCalled, isTrue);
      expect(repo.submittedCareReceiver!.medicalConditions,
          contains(MedicalCondition.other));
      expect(repo.submittedCareReceiver!.medicalConditionOther,
          'Recovering from hip surgery');
    });
  });

  testWidgets('Edit opens the form pre-filled with the job\'s full details',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"),
        findsOneWidget);
    expect(find.text('72'), findsOneWidget,
        reason: 'age should be pre-filled from the care receiver');
    expect(find.text('58'), findsOneWidget,
        reason: 'weight should be pre-filled from the care receiver');
    // Fixture's care_duration is 'few_weeks' -> derives Daily -> ₹/day.
    expect(
      find.widgetWithText(TextField, 'Salary (₹/day) (Mandatory)'),
      findsOneWidget,
    );
    final salaryField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Salary (₹/day) (Mandatory)'));
    expect(salaryField.controller!.text, '30000',
        reason: 'salary should be pre-filled from the job');
  });

  testWidgets(
      'Edit pre-fills the toilet-assistance "Others" free-text field from the existing care receiver',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final otherField = find.widgetWithText(
        TextField, 'Please describe the other toilet assistance');
    expect(otherField, findsOneWidget);
    expect(
      tester.widget<TextField>(otherField).controller!.text,
      'Needs help with a raised commode seat',
    );
  });

  testWidgets(
      'editing and saving calls repository.update() with the job id, not create()',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final area = find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)');
    await tester.ensureVisible(area);
    await tester.enterText(area, 'Koramangala');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.updatedJobId, 'job-1');
    expect(repo.createCalled, isFalse);
  });

  group(
      'Frequency of Care and Salary — always derived from Duration Care is Needed and Rate-Card-suggested, '
      'never admin-set manually, for every job admin creates or edits', () {
    testWidgets(
        'Frequency of Care is shown derived and read-only when editing any existing job, not a dropdown',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
      await _pump(tester, repo, rateCards: const []);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Frequency of Care'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
      // No mandatory-dropdown label for it anymore — it's derived, not picked.
      expect(find.text('Frequency of Care (Mandatory)'), findsNothing);
      expect(find.widgetWithText(DropdownButtonFormField<String>, 'Frequency of Care (Mandatory)'),
          findsNothing);
    });

    testWidgets(
        "Duration Care is Needed is also offered — and required — on admin's own from-scratch job posting, "
        'not just when editing a NurseNow individual\'s requirement', (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo, rateCards: const []);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      expect(
          find.widgetWithText(
              DropdownButtonFormField<String>, 'Duration Care is Needed (Mandatory)'),
          findsOneWidget);
      expect(
          find.widgetWithText(
              DropdownButtonFormField<String>, 'Frequency of Care (Mandatory)'),
          findsNothing);

      await _fillPatientDetailsCore(tester);
      await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
          '12Hrs Day Shift (8am to 8pm)');
      await _pickPreferredStartDate(tester);
      await _fillSalary(tester);
      await _tapChip(tester, 'Hindi');
      // Duration Care is Needed deliberately left untouched.

      final postButton = find.widgetWithText(ElevatedButton, 'Post');
      await tester.ensureVisible(postButton);
      await tester.tap(postButton);
      await tester.pumpAndSettle();

      expect(repo.createCalled, isFalse);
      expect(find.text('Please select how long care is needed'), findsOneWidget);
    });

    testWidgets('long_term derives to Monthly', (tester) async {
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'long_term');
      await _pump(tester, repo, rateCards: const []);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Monthly'), findsOneWidget);
    });

    testWidgets('Salary is pre-filled with the Rate Card suggestion for the derived tier/frequency',
        (tester) async {
      // _jobWithCareReceiver's toilet_assistance is ['others'] -> critical tier.
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
      await _pump(
        tester,
        repo,
        rateCards: [
          _rateCardWithUpdater(
              frequencyOfCare: FrequencyOfCare.daily,
              companion: 'DAILY_COMPANION',
              critical: 'DAILY_CRITICAL_RATE'),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), findsOneWidget);
      expect(find.text('30000'), findsNothing,
          reason: 'the fixture salary should be overridden by the suggestion');
    });

    testWidgets('falls back to the existing salary_amount when the Rate Card fetch fails', (tester) async {
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
      await _pump(tester, repo, rateCardError: Exception('network down'));

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '30000'), findsOneWidget);
    });

    testWidgets('the pre-filled suggestion stays freely editable and is what gets submitted', (tester) async {
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
      await _pump(
        tester,
        repo,
        rateCards: [
          _rateCardWithUpdater(
              frequencyOfCare: FrequencyOfCare.daily,
              companion: 'DAILY_COMPANION',
              critical: 'DAILY_CRITICAL_RATE'),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), '35000 negotiable');
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repo.updatedJobId, 'job-1');
      expect(repo.submittedFrequencyOfCare, 'daily');
      expect(repo.submittedSalaryAmount, '35000 negotiable');
    });

    testWidgets('a blank salary blocks submission with a validation error, not the numeric-range message',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
      await _pump(tester, repo, rateCards: const []);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '30000'), '');
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Changes');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Salary is required'), findsOneWidget);
      expect(repo.updatedJobId, isNull);
    });

    testWidgets(
        'reactively re-suggests Salary as Toilet Assistance is changed to a higher tier, on a from-scratch '
        'posting just like nursenow-app\'s own reactive suggestion', (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(
        tester,
        repo,
        rateCards: [
          _rateCardWithUpdater(
              frequencyOfCare: FrequencyOfCare.daily,
              companion: 'DAILY_COMPANION',
              critical: 'DAILY_CRITICAL_RATE'),
        ],
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      // Deliberately doesn't call _fillMandatoryFields (which would type
      // over the Salary field) — only picks Duration Care is Needed, so the
      // auto-suggestion can be observed untouched.
      await _fillPatientDetailsCore(tester);
      await _selectDropdown(tester, 'Hours Care Needed (Mandatory)',
          '12Hrs Day Shift (8am to 8pm)');
      await _pickPreferredStartDate(tester);
      await _selectDropdown(
          tester, 'Duration Care is Needed (Mandatory)', 'Need for Few Weeks');

      // No toilet assistance selected yet -> Companion tier, Daily.
      expect(find.widgetWithText(TextField, 'DAILY_COMPANION'), findsOneWidget);

      await _selectDropdown(
          tester, 'Toilet Assistance (Mandatory)', 'Catheter support');

      expect(find.widgetWithText(TextField, 'DAILY_CRITICAL_RATE'), findsOneWidget);
    });
  });

  group(
      'Communication and Vital Monitoring are removed from admin-web\'s form entirely — the backend still '
      'defaults them server-side', () {
    testWidgets('not offered on a from-scratch Post New Job', (tester) async {
      final repo = _FakeAdminJobsRepository([]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
      await tester.pumpAndSettle();

      expect(find.text('Communication'), findsNothing);
      expect(find.text('Is regular vital monitoring required?'), findsNothing);
      expect(find.text(_descriptionLabel), findsNothing);
    });

    testWidgets(
        'not offered when editing an existing job, even one that already has non-default values set',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      await _pump(tester, repo);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Communication'), findsNothing);
      expect(find.text('Is regular vital monitoring required?'), findsNothing);
      expect(find.text(_descriptionLabel), findsNothing);
    });
  });

  testWidgets(
      'tapping outside the Edit dialog does not dismiss it or lose the in-progress edit',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final area = find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)');
    await tester.ensureVisible(area);
    await tester.enterText(area, 'Koramangala');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Edit ADMIN-JOB-542'), findsOneWidget);
    final areaField = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Area in Bangalore (Mandatory)'));
    expect(areaField.controller!.text, 'Koramangala');
    expect(repo.updatedJobId, isNull);
  });

  testWidgets(
      'Applicants dialog shows Accept/Reject for an applied application; Accept calls decideApplication',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()],
        applications: [_application(status: 'applied')]);
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

  testWidgets(
      'Applicants dialog shows only Reject for an already-accepted application',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'closed')],
        applications: [_application(status: 'accepted')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Kumar — accepted'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets(
      'Applicants dialog shows when the applicant applied, was accepted, and who accepted them',
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

    expect(find.text('Applied: ${_expectedDateTime('2026-08-01T10:00:00Z')}'),
        findsOneWidget);
    expect(
      find.text(
          'Accepted: ${_expectedDateTime('2026-08-02T11:30:00Z')} by Priya Admin'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Applicants dialog shows who declined a previously-accepted applicant, and when',
      (tester) async {
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
      find.text(
          'Declined by Priya Admin: ${_expectedDateTime('2026-08-03T09:15:00Z')}'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Applicants dialog shows the decline reason when a NurseNow patient rejected the caregiver',
      (tester) async {
    final repo = _FakeAdminJobsRepository(
      [_job()],
      applications: [
        _application(
          status: 'rejected',
          appliedAt: '2026-08-01T10:00:00Z',
          rejectedAt: '2026-08-03T09:15:00Z',
          decidedByName: 'Asha Patel',
          declineReason: 'Not available on the requested days',
        ),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Reason: Not available on the requested days'), findsOneWidget);
  });

  testWidgets(
      'tapping the job row opens a read-only detail view, not the editable form',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: null);
    await _pump(tester, repo);

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Patient Details')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Care Preferences')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Nurse Fee Guidance')),
        findsOneWidget);
    expect(
        find.descendant(of: dialog, matching: find.text('Hours Care Needed')),
        findsOneWidget);
    expect(
        find.descendant(
            of: dialog, matching: find.widgetWithText(ElevatedButton, 'Edit')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Close')),
        findsOneWidget);
    // Same field-set trim as the editable form — Communication, Vital
    // Monitoring, and the free-text description aren't shown here either,
    // even though this fixture's care_receiver has non-default values for
    // them (see _jobWithCareReceiver — communication: 'verbal' isn't
    // "None"/absent, it's just never rendered as a labeled row any more).
    expect(find.descendant(of: dialog, matching: find.text('Communication')),
        findsNothing);
    expect(
        find.descendant(of: dialog, matching: find.text('Vital Monitoring')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('More Details')),
        findsNothing);
    // Read-only: no editable form fields, no Save Changes button, no
    // "Edit ADMIN-JOB-542" dialog title (that's the editable form's title).
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsNothing);
    expect(find.text('Edit ADMIN-JOB-542'), findsNothing);
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"),
        findsNothing);
    // Not set on this fixture (detailCareDuration: null) — a legacy job
    // that predates the field.
    expect(find.text('Duration Care is Needed'), findsNothing);
  });

  testWidgets(
      'the read-only detail view shows Duration Care is Needed for a NurseNow individual posting that sets it',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()], detailCareDuration: 'few_weeks');
    await _pump(tester, repo);

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Duration Care is Needed')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Need for Few Weeks')), findsOneWidget);
  });

  testWidgets(
      'the read-only detail view shows a Scope of Work button that pops up the derived tier',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    // _jobWithCareReceiver's toilet_assistance is ['others'] — derives to
    // Critical Care (stacked with Companion + Bedside), since "Others"
    // toileting is one of the criticalCare triggers.
    // find.text('Scope of Work') alone is ambiguous — it also matches the
    // row's own label and the AppShell sidebar nav item — so target the
    // button specifically.
    final button = find.widgetWithText(OutlinedButton, 'Scope of Work');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Critical Care'), findsOneWidget);
    expect(find.text('Emotional companionship'), findsOneWidget);
    expect(find.text('Diaper changing & hygiene care'), findsOneWidget);
    expect(find.text('Catheter care'), findsOneWidget);
  });

  testWidgets(
      'tapping Edit inside the read-only detail view opens the editable form',
      (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    final readOnlyDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(
        of: readOnlyDialog,
        matching: find.widgetWithText(ElevatedButton, 'Edit')));
    await tester.pumpAndSettle();

    expect(find.text('Edit ADMIN-JOB-542'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    // Exactly one dialog on screen — the read-only one was popped first,
    // not left stacked underneath the editable form.
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  group('merged with organisation requirements', () {
    testWidgets(
        'a job and an organisation requirement both render in the same list, newest first',
        (tester) async {
      final repo =
          _FakeAdminJobsRepository([_job(postedAt: '2026-08-01T09:00:00Z')]);
      final requirementsRepo = _FakeAdminOrganisationRequirementsRepository([
        _requirement(postedAt: '2026-08-02T09:00:00Z'),
      ]);
      await _pump(tester, repo, requirementsRepo: requirementsRepo);

      expect(find.text('ADMIN-JOB-542'), findsOneWidget);
      expect(find.text('ORG-JOB-101'), findsOneWidget);
      // Newer entries sort first — the requirement (Aug 2) appears above the
      // job (Aug 1) in the list.
      final requirementY = tester.getTopLeft(find.text('ORG-JOB-101')).dy;
      final jobY = tester.getTopLeft(find.text('ADMIN-JOB-542')).dy;
      expect(requirementY, lessThan(jobY));
    });

    testWidgets('by default (All jobs) both sources are fetched on load',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      final requirementsRepo =
          _FakeAdminOrganisationRequirementsRepository([_requirement()]);
      await _pump(tester, repo, requirementsRepo: requirementsRepo);

      expect(repo.lastListFilters, isNotNull);
      expect(requirementsRepo.listCallCount, 1);
    });

    testWidgets(
        'selecting "Patients" under Posted By only fetches jobs (posted_by_role=individual), '
        'skipping organisation requirements entirely', (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      final requirementsRepo =
          _FakeAdminOrganisationRequirementsRepository([_requirement()]);
      await _pump(tester, repo, requirementsRepo: requirementsRepo);

      expect(requirementsRepo.listCallCount, 1,
          reason: 'initial load with All jobs fetches both');

      await _selectFilterDropdown(tester, 'Posted By', 'Patients');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        repo.lastListFilters,
        isA<JobListFilters>()
            .having((f) => f.postedByRole, 'postedByRole', 'individual'),
      );
      expect(requirementsRepo.listCallCount, 1,
          reason: 'org requirements should not be re-fetched for Patients');
      expect(find.text('ORG-JOB-101'), findsNothing);
    });

    testWidgets(
        'selecting "Hospital" under Posted By only fetches organisation requirements '
        '(organisation_type=hospital), skipping jobs entirely', (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      final requirementsRepo =
          _FakeAdminOrganisationRequirementsRepository([_requirement()]);
      await _pump(tester, repo, requirementsRepo: requirementsRepo);

      expect(repo.listCallCount, 1,
          reason: 'initial load with All jobs fetches both');

      await _selectFilterDropdown(tester, 'Posted By', 'Hospital');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Filters'));
      await tester.pumpAndSettle();

      expect(
        requirementsRepo.lastFilters,
        isA<OrganisationRequirementListFilters>()
            .having((f) => f.organisationType, 'organisationType', 'hospital'),
      );
      expect(repo.listCallCount, 1,
          reason: 'jobs should not be re-fetched for Hospital');
      expect(find.text('ADMIN-JOB-542'), findsNothing);
      expect(find.text('ORG-JOB-101'), findsOneWidget);
    });
  });

  group(
      '"View Jobs" redirect from a single Rehab/Hospitals or Patients/Family row',
      () {
    testWidgets(
        'an organisation initialFilter scopes to just that organisation\'s requirements '
        '(organisation_type + posted_by), skipping jobs entirely, and shows a clearable banner',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      final requirementsRepo =
          _FakeAdminOrganisationRequirementsRepository([_requirement()]);
      await _pump(
        tester,
        repo,
        requirementsRepo: requirementsRepo,
        initialFilter: const JobsScreenInitialFilter(
          postedByUserId: 'org-user-1',
          postedByLabel: 'City Rehab Center',
          organisationType: OrganisationType.rehab,
        ),
      );

      expect(repo.listCallCount, 0,
          reason: 'jobs must not be fetched when scoped to one organisation');
      expect(
        requirementsRepo.lastFilters,
        isA<OrganisationRequirementListFilters>()
            .having((f) => f.postedBy, 'postedBy', 'org-user-1')
            .having((f) => f.organisationType, 'organisationType', 'rehab'),
      );
      expect(
          find.text('Showing postings by: City Rehab Center'), findsOneWidget);
      expect(find.text('ADMIN-JOB-542'), findsNothing);
      expect(find.text('ORG-JOB-101'), findsOneWidget);

      // Clearing drops the specific-poster narrowing but keeps browsing
      // scoped to organisation requirements (the broader Posted By type
      // filter it was seeded with stays put).
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Showing postings by: City Rehab Center'), findsNothing);
      expect(
        requirementsRepo.lastFilters,
        isA<OrganisationRequirementListFilters>()
            .having((f) => f.postedBy, 'postedBy', isNull)
            .having((f) => f.organisationType, 'organisationType', 'rehab'),
      );
    });

    testWidgets(
        'an individual initialFilter scopes to just that patient\'s jobs '
        '(posted_by_role=individual + posted_by), skipping organisation requirements entirely',
        (tester) async {
      final repo = _FakeAdminJobsRepository([_job()]);
      final requirementsRepo =
          _FakeAdminOrganisationRequirementsRepository([_requirement()]);
      await _pump(
        tester,
        repo,
        requirementsRepo: requirementsRepo,
        initialFilter: const JobsScreenInitialFilter(
          postedByUserId: 'patient-user-1',
          postedByLabel: 'Rahul Bajaj',
        ),
      );

      expect(requirementsRepo.listCallCount, 0,
          reason:
              'org requirements must not be fetched when scoped to one individual');
      expect(
        repo.lastListFilters,
        isA<JobListFilters>()
            .having((f) => f.postedBy, 'postedBy', 'patient-user-1')
            .having((f) => f.postedByRole, 'postedByRole', 'individual'),
      );
      expect(find.text('Showing postings by: Rahul Bajaj'), findsOneWidget);
      expect(find.text('ORG-JOB-101'), findsNothing);
      expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    });
  });
}
