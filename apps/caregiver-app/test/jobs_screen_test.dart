import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';
import 'package:caregiver_app/features/jobs/screens/job_preferences_screen.dart';
import 'package:caregiver_app/features/jobs/widgets/job_detail_card.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';

// Same conversion the app applies (UTC -> local) so assertions don't
// depend on the test machine's timezone.
String _expected(String isoUtc) => formatDateTime(DateTime.parse(isoUtc).toLocal());

JobModel _job({
  Map<String, dynamic>? myApplication,
  String? postedAt,
  Object? description = 'Need a caregiver for an elderly patient',
  String frequencyOfCare = 'daily',
  String? startDate,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': description,
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': startDate,
    'languages': ['hindi'],
    'salary_amount': 30000,
    'preferred_gender': 'female',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': postedAt ?? DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': myApplication,
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'mobility': 'uses_wheelchair',
      'communication': 'verbal',
      'feeding_type': 'oral_needs_assistance',
      'medical_assistance': ['medication_reminders'],
      'has_medical_condition': true,
      'medical_conditions': ['diabetes'],
      'medical_condition_other': 'Recovering from hip surgery',
      'toilet_assistance': ['uses_diapers', 'uses_catheter'],
      'toilet_assistance_other': 'Needs a raised commode seat',
      'requires_vital_monitoring': true,
      'vital_monitoring_types': ['blood_pressure', 'blood_sugar'],
    },
  });
}

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 7,
  int? salaryAmount = 40000,
  String? frequencyOfCare = 'monthly',
  String? postedAt,
  String? scheduleType,
  String? startDate,
  String? endDate,
  String? scheduleRepeat,
  List<int>? specificDays,
  Map<String, dynamic>? myApplication,
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'frequency_of_care': frequencyOfCare,
    'salary_amount': salaryAmount,
    'schedule_type': scheduleType,
    'start_date': startDate,
    'end_date': endDate,
    'schedule_repeat': scheduleRepeat,
    'specific_days': specificDays,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Post-surgery wound care',
    'status': 'active',
    'posted_at': postedAt ?? '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'my_application': myApplication,
  });
}

class _FakeJobsRepository extends JobsRepository {
  List<JobModel> jobs;
  String? appliedWith;
  int listActiveJobsCallCount = 0;

  _FakeJobsRepository(this.jobs) : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async {
    listActiveJobsCallCount++;
    return jobs;
  }

  @override
  Future<String> applyToJob(String jobId, String status) async {
    appliedWith = status;
    jobs = [
      _job(myApplication: {
        'status': status,
        'applied_at': status == 'applied' ? '2026-08-17T10:00:00Z' : null,
        'accepted_at': null,
        'rejected_at': status == 'rejected' ? '2026-08-17T10:00:00Z' : null,
        'decided_by_admin': false,
      }),
    ];
    return status;
  }
}

class _FakeOrganisationOpeningsRepository extends OrganisationOpeningsRepository {
  List<OrganisationRequirementModel> requirements;
  String? appliedWith;

  _FakeOrganisationOpeningsRepository([this.requirements = const []]) : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> listActive() async => requirements;

  @override
  Future<String> apply(String requirementId, String status) async {
    appliedWith = status;
    return status;
  }
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository() : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => CaregiverProfileModel.fromJson({
        'user_id': 'u1',
        'profile_id': 'p1',
        'full_name': 'Test Caregiver',
        'phone': '+919876543210',
        'gender': 'male',
        'age': 30,
        'languages': ['hindi'],
        'other_document_urls': [],
        'terms_accepted': true,
        'verification_status': 'available',
        'created_at': '2026-08-01T10:00:00Z',
        'preferred_cities': [],
        'preferred_duty_types': [],
      });

  @override
  Future<String> editProfile({
    int? age,
    List<String>? languages,
    String? highestQualification,
    List<String>? preferredCities,
    List<String>? preferredDutyTypes,
    int? minSalaryPerDay,
    int? minSalaryPerMonth,
  }) async =>
      'available';
}

Future<void> _pump(
  WidgetTester tester,
  _FakeJobsRepository jobsRepo, {
  _FakeOrganisationOpeningsRepository? orgRepo,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(jobsRepo),
        organisationOpeningsRepositoryProvider.overrideWithValue(orgRepo ?? _FakeOrganisationOpeningsRepository()),
        ...extraOverrides,
      ],
      child: const MaterialApp(home: JobsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

// JobDetailCard is collapsed by default; tests that need the About
// Patient/About Nurse-Caregiver Requirement detail must expand it first.
Future<void> _expandDetails(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.text('Show details').at(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'job cards start collapsed (About Patient/Requirement hidden) and expand/collapse on tap, '
      'so cards are distinguishable when scanning a list of many', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    // Collapsed: header (job #, salary, duty type + city, posted date) is
    // visible, but the tag-heavy detail sections are not.
    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('24Hrs - Live In in Bangalore'), findsOneWidget);
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('About Nurse/Caregiver Requirement'), findsNothing);
    expect(find.text('Show details'), findsOneWidget);

    await tester.tap(find.text('Show details'));
    await tester.pumpAndSettle();

    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    expect(find.text('Show details'), findsNothing);

    await tester.tap(find.text('Hide details'));
    await tester.pumpAndSettle();

    expect(find.text('About Patient'), findsNothing);
    expect(find.text('About Nurse/Caregiver Requirement'), findsNothing);
    expect(find.text('Show details'), findsOneWidget);
  });

  testWidgets('shows job details: duty type, city, area, description', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.text('24Hrs - Live In in Bangalore'), findsOneWidget);
    // Area/description are inside the collapsible detail section.
    expect(find.text('Indiranagar'), findsNothing);
    expect(find.text('Need a caregiver for an elderly patient'), findsNothing);

    await _expandDetails(tester);

    expect(find.text('Indiranagar'), findsOneWidget);
    expect(find.text('Need a caregiver for an elderly patient'), findsOneWidget);
  });

  testWidgets('renders fine and shows no description line when the job has none set (now optional)',
      (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(description: null)]));
    await _expandDetails(tester);

    expect(find.text('24Hrs - Live In in Bangalore'), findsOneWidget);
    expect(find.text('Need a caregiver for an elderly patient'), findsNothing);
  });

  testWidgets(
      'groups patient identity/condition into one About Patient section, and caregiver requirement details into another',
      (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));
    await _expandDetails(tester);

    // About Patient — identity and condition are one merged section now,
    // not two separately labeled ones.
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('About Patient Condition'), findsNothing);
    expect(find.text('78 yrs'), findsOneWidget);
    expect(find.text('Female'), findsWidgets); // patient gender tag + preferred-gender tag
    expect(find.text('60 kg'), findsOneWidget);
    expect(find.text('Uses wheelchair'), findsOneWidget);
    expect(find.text('Can Speak/Communicate'), findsOneWidget);
    expect(find.text('Oral feeding – needs assistance'), findsOneWidget);
    expect(find.text('Medicine Reminders'), findsOneWidget);
    expect(find.text('Toilet: Uses diapers'), findsOneWidget);
    expect(find.text('Toilet: Uses catheter'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(find.text('Monitor: Blood pressure'), findsOneWidget);
    expect(find.text('Monitor: Blood sugar'), findsOneWidget);
    expect(find.text('Other condition: Recovering from hip surgery'), findsOneWidget);
    expect(find.text('Other toilet assistance: Needs a raised commode seat'), findsOneWidget);

    // About Nurse/Caregiver Requirement
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget);
  });

  testWidgets('does not show the "other" detail lines when the care receiver has none set', (tester) async {
    final job = JobModel.fromJson({
      'id': 'job-1',
      'job_number': 42,
      'city': 'bangalore',
      'area': 'Indiranagar',
      'description': 'Need a caregiver for an elderly patient',
      'duty_type': 'live_in',
      'frequency_of_care': 'daily',
      'languages': ['hindi'],
      'salary_amount': 30000,
      'preferred_gender': 'female',
      'status': 'active',
      'posted_by': 'admin-1',
      'posted_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': '2026-08-01T10:00:00Z',
      'care_receiver': {
        'id': 'cr-1',
        'age': 78,
        'gender': 'female',
        'weight_kg': 60,
        'mobility': 'uses_wheelchair',
        'communication': 'verbal',
        'feeding_type': 'oral_needs_assistance',
        'medical_assistance': ['medication_reminders'],
        'has_medical_condition': false,
        'medical_conditions': [],
        'toilet_assistance': ['uses_diapers'],
        'requires_vital_monitoring': false,
        'vital_monitoring_types': [],
      },
    });
    await _pump(tester, _FakeJobsRepository([job]));
    await _expandDetails(tester);

    expect(find.textContaining('Other condition:'), findsNothing);
    expect(find.textContaining('Other toilet assistance:'), findsNothing);
  });

  testWidgets('shows the job number and salary highlighted at the top', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.text('Job #42'), findsOneWidget);
    // Fixture's frequency_of_care is 'daily' — the unit follows it.
    expect(find.text('₹30000/day'), findsOneWidget);
  });

  testWidgets('shows a highlighted start date next to the salary when the job has one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([_job(startDate: '2026-08-20')])),
          organisationOpeningsRepositoryProvider.overrideWithValue(_FakeOrganisationOpeningsRepository()),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    // Not pumpAndSettle: the start date badge blinks via a repeating
    // AnimationController by design, so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('₹30000/day'), findsOneWidget);
    expect(find.text('Start: 2026-08-20'), findsOneWidget);
  });

  testWidgets('shows the start date in red, same size as the salary label, on the job card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([_job(startDate: '2026-08-20')])),
          organisationOpeningsRepositoryProvider.overrideWithValue(_FakeOrganisationOpeningsRepository()),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final salaryStyle = tester.widget<Text>(find.text('₹30000/day')).style!;
    final startDateStyle = tester.widget<Text>(find.text('Start: 2026-08-20')).style!;
    expect(startDateStyle.color, AppColors.error);
    expect(startDateStyle.fontSize, salaryStyle.fontSize);
  });

  testWidgets(
      'shows a highlighted red date range next to the salary for an organisation requirement on a date_range schedule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([])),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _requirement(scheduleType: 'date_range', startDate: '2026-08-25', endDate: '2026-09-05'),
            ]),
          ),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('₹40000/month'), findsOneWidget);
    expect(find.text('2026-08-25 – 2026-09-05'), findsOneWidget);
    final salaryStyle = tester.widget<Text>(find.text('₹40000/month')).style!;
    final scheduleStyle = tester.widget<Text>(find.text('2026-08-25 – 2026-09-05')).style!;
    expect(scheduleStyle.color, AppColors.error);
    expect(scheduleStyle.fontSize, salaryStyle.fontSize);
  });

  testWidgets(
      'shows a highlighted red day list for an organisation requirement on a specific_days/monthly schedule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([])),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _requirement(scheduleType: 'specific_days', scheduleRepeat: 'monthly', specificDays: [3, 12, 20]),
            ]),
          ),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Days: 3, 12, 20'), findsOneWidget);
    final scheduleStyle = tester.widget<Text>(find.text('Days: 3, 12, 20')).style!;
    expect(scheduleStyle.color, AppColors.error);
  });

  testWidgets(
      'shows a highlighted red weekday list for an organisation requirement on a specific_days/weekly schedule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([])),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _requirement(scheduleType: 'specific_days', scheduleRepeat: 'weekly', specificDays: [1, 3, 5]),
            ]),
          ),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Every: Mon, Wed, Fri'), findsOneWidget);
    final scheduleStyle = tester.widget<Text>(find.text('Every: Mon, Wed, Fri')).style!;
    expect(scheduleStyle.color, AppColors.error);
  });

  testWidgets('shows the salary unit as /month for a job with frequency_of_care monthly', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(frequencyOfCare: 'monthly')]));

    expect(find.text('₹30000/month'), findsOneWidget);
  });

  testWidgets('shows days-left urgency for a freshly-posted job', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job(postedAt: DateTime.now().toUtc().toIso8601String())]),
    );
    expect(find.textContaining('left to apply'), findsOneWidget);
  });

  testWidgets('shows "window closed" once the 3-day apply-by window has passed (informational only)',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(postedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)).toIso8601String()),
      ]),
    );
    expect(find.text('Application window closed'), findsOneWidget);
    // Informational only — Apply/Reject stay active even past the window.
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
  });

  testWidgets('shows Apply/Reject when the caregiver has not applied yet', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'More Info'), findsNothing);
  });

  testWidgets('shows the applied date instead of buttons once already applied', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'applied',
          'applied_at': '2026-08-17T10:00:00Z',
          'accepted_at': null,
          'rejected_at': null,
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Applied: ${_expected('2026-08-17T10:00:00Z')}'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsNothing);
  });

  testWidgets('shows "Declined" (not "Declined by employer") when the caregiver declined it themselves',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-17T09:00:00Z',
          'accepted_at': null,
          'rejected_at': '2026-08-17T09:05:00Z',
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Applied: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined: ${_expected('2026-08-17T09:05:00Z')}'), findsOneWidget);
    expect(find.textContaining('Declined by employer'), findsNothing);
  });

  testWidgets(
      'shows the full real timeline — applied, accepted, then "Declined by employer" — not a bare '
      '"You declined" when an admin undoes a prior acceptance', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-15T09:00:00Z',
          'accepted_at': '2026-08-16T09:00:00Z',
          'rejected_at': '2026-08-17T09:00:00Z',
          'decided_by_admin': true,
        }),
      ]),
    );

    expect(find.text('Applied: ${_expected('2026-08-15T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Accepted: ${_expected('2026-08-16T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined by employer: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('You declined'), findsNothing);
  });

  testWidgets('tapping Apply calls applyToJob with applied', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'applied');
  });

  testWidgets('tapping Reject calls applyToJob with rejected', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'rejected');
  });

  testWidgets('shows an empty state when there are no active jobs or organisation requirements', (tester) async {
    await _pump(tester, _FakeJobsRepository([]));

    expect(find.textContaining('No jobs posted right now'), findsOneWidget);
  });

  testWidgets('tapping the gear icon opens Job Search Preferences', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      extraOverrides: [profileRepositoryProvider.overrideWithValue(_FakeProfileRepository())],
    );

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.byType(JobPreferencesScreen), findsOneWidget);
    expect(find.text('Job Search Preferences'), findsOneWidget);
  });

  testWidgets('reloads the job list after saving preferences', (tester) async {
    final fakeJobsRepo = _FakeJobsRepository([_job()]);
    await _pump(
      tester,
      fakeJobsRepo,
      extraOverrides: [profileRepositoryProvider.overrideWithValue(_FakeProfileRepository())],
    );
    expect(fakeJobsRepo.listActiveJobsCallCount, 1);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Mumbai'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(JobPreferencesScreen), findsNothing);
    expect(fakeJobsRepo.listActiveJobsCallCount, 2);
  });

  // --- Merged organisation requirements ---

  testWidgets('shows organisation requirements alongside jobs in the same list — no separate tab', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('Requirement #7'), findsOneWidget);
    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('Hospital · Bangalore · Indiranagar'), findsOneWidget);
    expect(find.text('₹40000/month'), findsOneWidget);
    expect(find.text('Registered Nurse'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Post-surgery wound care'), findsOneWidget);
  });

  testWidgets('sorts jobs and organisation requirements together by posted date, newest first', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job(postedAt: '2026-08-10T10:00:00Z')]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement(postedAt: '2026-08-15T10:00:00Z')]),
    );

    final jobCenter = tester.getCenter(find.text('Job #42'));
    final requirementCenter = tester.getCenter(find.text('Requirement #7'));
    expect(requirementCenter.dy, lessThan(jobCenter.dy));
  });

  testWidgets('tapping Apply on a requirement calls the organisation repository with applied', (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository([_requirement()]);
    await _pump(tester, _FakeJobsRepository([]), orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(orgRepo.appliedWith, 'applied');
  });

  testWidgets('tapping Reject on a requirement calls the organisation repository with rejected', (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository([_requirement()]);
    await _pump(tester, _FakeJobsRepository([]), orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(orgRepo.appliedWith, 'rejected');
  });

  testWidgets('shows the applied timeline instead of buttons for a requirement once already applied',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([
        _requirement(myApplication: {
          'status': 'applied',
          'applied_at': '2026-08-17T10:00:00Z',
          'accepted_at': null,
          'rejected_at': null,
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Applied: ${_expected('2026-08-17T10:00:00Z')}'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsNothing);
  });
}
