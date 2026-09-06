import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:caregiver_app/core/caregiver_messages/caregiver_messages_repository.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/scope_of_work/scope_of_work_repository.dart';
import 'package:caregiver_app/core/duty_requirements/duty_requirements_repository.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';
import 'package:caregiver_app/features/jobs/widgets/job_detail_card.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';

class _FakeCaregiverMessagesRepository extends CaregiverMessagesRepository {
  _FakeCaregiverMessagesRepository() : super(Dio());

  @override
  Future<List<CaregiverMessageModel>> get() async => const [];
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => const ScopeOfWorkModel(
        companionCare: ['Companion bullet'],
        bedsideCare: ['Bedside bullet'],
        criticalCare: ['Critical bullet'],
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

// Same conversion the app applies (UTC -> local) so assertions don't
// depend on the test machine's timezone.
String _expected(String isoUtc) => formatDateTime(DateTime.parse(isoUtc).toLocal());

JobModel _job({
  Map<String, dynamic>? myApplication,
  String? postedAt,
  Object? description = 'Need a caregiver for an elderly patient',
  String frequencyOfCare = 'daily',
  String? startDate,
  String? careDuration,
  int? applicantCount,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'admin_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': description,
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': startDate,
    'care_duration': careDuration,
    'languages': ['hindi'],
    'salary_amount': '30000',
    'preferred_gender': 'female',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': postedAt ?? DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': myApplication,
    'applicant_count': applicantCount,
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'feeding_type': 'oral_feeding',
      'has_medical_condition': true,
      'medical_conditions': ['diabetes'],
      'medical_condition_other': 'Recovering from hip surgery',
      'toilet_assistance': ['diapers_bedside_support', 'uses_catheter'],
      'toilet_assistance_other': 'Needs a raised commode seat',
      'requires_vital_monitoring': true,
      'vital_monitoring_types': ['blood_pressure', 'blood_sugar'],
    },
  });
}

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 7,
  String? postedAt,
  Map<String, dynamic>? myApplication,
  int? applicantCount,
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Post-surgery wound care',
    'number_of_vacancies': 1,
    'status': 'active',
    'posted_at': postedAt ?? '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'my_application': myApplication,
    'applicant_count': applicantCount,
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
  Future<List<JobModel>> getAssignedJobs() async => const [];

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

Future<void> _pump(
  WidgetTester tester,
  _FakeJobsRepository jobsRepo, {
  _FakeOrganisationOpeningsRepository? orgRepo,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(jobsRepo),
        organisationOpeningsRepositoryProvider.overrideWithValue(orgRepo ?? _FakeOrganisationOpeningsRepository()),
        localStorageProvider.overrideWithValue(localStorage),
        caregiverMessagesRepositoryProvider.overrideWithValue(_FakeCaregiverMessagesRepository()),
        ...extraOverrides,
      ],
      child: const MaterialApp(home: JobsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

// JobDetailCard's header is compact by default; tests that need the About
// Patient/About Nurse-Caregiver Requirement detail must open the full-screen
// detail view first.
Future<void> _expandDetails(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.text('View Full Details about Patient Requirements').at(index));
  await tester.pumpAndSettle();
}

// A job/requirement the caregiver was rejected from (by either side) is
// hidden by default — tests exercising its card content must reveal it via
// the "Show All Jobs" toggle first.
Future<void> _showAllJobs(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(SwitchListTile, 'Show All Jobs'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'job cards show a compact header (About Patient/Requirement hidden) and open a full-screen '
      'detail view on tap, with a clear way back out', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    // Compact header (job #, salary, duty type + city/area, posted date) is
    // visible on the card, but the tag-heavy detail sections are not.
    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Bangalore · Indiranagar'), findsOneWidget);
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('About Nurse/Caregiver Requirement'), findsNothing);
    expect(find.text('View Full Details about Patient Requirements'), findsOneWidget);

    await tester.tap(find.text('View Full Details about Patient Requirements'));
    await tester.pumpAndSettle();

    // Full-screen detail view: same header content repeated, plus the full
    // About Patient / About Nurse-Caregiver Requirement sections, plus a
    // back button to leave the full-screen view.
    expect(find.byType(JobFullDetailScreen), findsOneWidget);
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(JobFullDetailScreen), findsNothing);
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('About Nurse/Caregiver Requirement'), findsNothing);
    expect(find.text('View Full Details about Patient Requirements'), findsOneWidget);
  });

  testWidgets(
      'shows Job Id, Type Of Care, and Scope Of Work / Patient Provides links just below Hours Care Needed, '
      'Duration Care Is Needed, and City', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      extraOverrides: [
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
      ],
    );

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    // _job()'s care_receiver uses a catheter, which always derives to
    // Critical Care regardless of anything else selected.
    expect(find.text('Type Of Care: Critical Care'), findsOneWidget);
    expect(find.text('Scope Of Work: Click Here'), findsOneWidget);
    expect(find.text('Patient Provides: Click Here'), findsOneWidget);

    await tester.tap(find.text('Scope Of Work: Click Here'));
    await tester.pumpAndSettle();
    expect(find.text('Critical bullet'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient Provides: Click Here'));
    await tester.pumpAndSettle();
    expect(find.text('Live-in bullet'), findsOneWidget);
  });

  testWidgets(
      'does not show Type Of Care or Scope Of Work when the job has no care receiver, '
      'but Patient Provides always shows', (tester) async {
    final job = JobModel.fromJson({
      'id': 'job-1',
      'admin_job_number': 542,
      'city': 'bangalore',
      'duty_type': 'live_in',
      'frequency_of_care': 'daily',
      'languages': ['hindi'],
      'status': 'active',
      'posted_by': 'admin-1',
      'posted_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': '2026-08-01T10:00:00Z',
    });
    await _pump(
      tester,
      _FakeJobsRepository([job]),
      extraOverrides: [
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
      ],
    );

    expect(find.textContaining('Type Of Care'), findsNothing);
    expect(find.textContaining('Scope Of Work'), findsNothing);
    expect(find.text('Patient Provides: Click Here'), findsOneWidget);
  });

  testWidgets('labels an admin-posted job "Posted by Admin"', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));
    expect(find.text('Job in Posted by Admin'), findsOneWidget);
    expect(find.textContaining('Home Care'), findsNothing);
  });

  testWidgets('labels a patient-posted job "Home Care"', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        JobModel.fromJson({
          'id': 'job-2',
          'patient_job_number': 701,
          'city': 'bangalore',
          'duty_type': 'live_in',
          'frequency_of_care': 'daily',
          'languages': ['hindi'],
          'status': 'active',
          'posted_by': 'individual-1',
          'posted_at': DateTime.now().toUtc().toIso8601String(),
          'created_at': '2026-08-01T10:00:00Z',
          'care_receiver': {
            'id': 'cr-2',
            'age': 70,
            'gender': 'male',
            'weight_kg': 65,
            'feeding_type': 'oral_feeding',
            'has_medical_condition': false,
            'medical_conditions': [],
            'toilet_assistance': ['independent'],
            'requires_vital_monitoring': false,
            'vital_monitoring_types': [],
          },
        }),
      ]),
    );
    expect(find.text('Job in Home Care'), findsOneWidget);
    expect(find.textContaining('Posted by Admin'), findsNothing);
  });

  testWidgets('labels an organisation requirement with its organisation type (e.g. Hospital)', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );
    expect(find.text('Hospital'), findsOneWidget);
  });

  testWidgets('shows job details: duty type, city, area, description', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    // City + area are shown together, up front in the collapsed header —
    // not buried in the collapsible detail section like description is.
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Bangalore · Indiranagar'), findsOneWidget);
    expect(find.text('Need a caregiver for an elderly patient'), findsNothing);

    await _expandDetails(tester);

    expect(find.text('Need a caregiver for an elderly patient'), findsOneWidget);
  });

  testWidgets('shows "N applied" next to the job id when applicant_count is set', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(applicantCount: 3)]));

    expect(find.textContaining('3 applied'), findsOneWidget);
  });

  testWidgets('shows no applicant count line for a job when applicant_count is not set', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.textContaining('applied'), findsNothing);
  });

  testWidgets('shows "N applied" next to the requirement id when applicant_count is set', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement(applicantCount: 5)]),
    );

    expect(find.textContaining('5 applied'), findsOneWidget);
  });

  testWidgets('renders fine and shows no description line when the job has none set (now optional)',
      (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(description: null)]));
    await _expandDetails(tester);

    // Duty type only appears once now — the collapsed header's icon field —
    // since it's no longer duplicated as its own Tag in the expanded "About
    // Nurse/Caregiver Requirement" section.
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Bangalore · Indiranagar'), findsOneWidget);
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
    // The preferred-gender tag is now labeled "Preferred Gender: Female",
    // not bare "Female", so this is just the patient's own gender tag.
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('60 kg'), findsOneWidget);
    expect(find.text('Oral feeding'), findsOneWidget);
    expect(find.text('Medicine Reminders'), findsNothing);
    expect(find.text('Toilet: Diapers/bedside support'), findsOneWidget);
    expect(find.text('Toilet: Catheter support'), findsOneWidget);
    // Area moved out of this section — it's shown next to City in the
    // collapsed header now (see the "shows job details" test).
    expect(find.text('Area: Indiranagar'), findsNothing);
    expect(find.text('Medical Condition: Diabetes'), findsOneWidget);
    expect(find.text('Monitor: Blood pressure'), findsOneWidget);
    expect(find.text('Monitor: Blood sugar'), findsOneWidget);
    expect(find.text('Other condition: Recovering from hip surgery'), findsOneWidget);
    expect(find.text('Other toilet assistance: Needs a raised commode seat'), findsOneWidget);

    // About Nurse/Caregiver Requirement
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    // Duty type and Frequency of Care are no longer shown here — Duty type
    // only appears once, as the collapsed header's icon field; Frequency of
    // Care isn't shown at all any more.
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Daily'), findsNothing);
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('Preferred Gender: Female'), findsOneWidget);
    // Not set on this fixture.
    expect(find.textContaining('Preferred Religion:'), findsNothing);
    // Not set on this admin-posted job fixture — only a NurseNow
    // individual's own posting sets care_duration.
    expect(find.text('Need for Few Weeks'), findsNothing);
  });

  testWidgets('shows the Duration Care is Needed tag for a NurseNow individual posting that sets it',
      (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(careDuration: 'few_weeks')]));

    // Visible up front, in the collapsed header, next to "Hours Care
    // Needed" — not just in the expanded "About Nurse/Caregiver
    // Requirement" section.
    expect(find.text('Need for Few Weeks'), findsOneWidget);

    await _expandDetails(tester);

    // Now shown twice — the collapsed header tag plus the expanded
    // section's own Tag.
    expect(find.text('Need for Few Weeks'), findsNWidgets(2));
  });

  testWidgets('does not show a Duration Care Is Needed tag for an admin-posted job (careDuration is null)',
      (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.textContaining('Need for'), findsNothing);
  });

  testWidgets('does not show the "other" detail lines when the care receiver has none set', (tester) async {
    final job = JobModel.fromJson({
      'id': 'job-1',
      'admin_job_number': 542,
      'city': 'bangalore',
      'area': 'Indiranagar',
      'description': 'Need a caregiver for an elderly patient',
      'duty_type': 'live_in',
      'frequency_of_care': 'daily',
      'languages': ['hindi'],
      'salary_amount': '30000',
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
        'feeding_type': 'oral_feeding',
        'has_medical_condition': false,
        'medical_conditions': [],
        'toilet_assistance': ['diapers_bedside_support'],
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

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    // Fixture's frequency_of_care is 'daily' — the unit follows it.
    expect(find.text('30000/day'), findsOneWidget);
  });

  testWidgets('shows a highlighted start date next to the salary when the job has one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([_job(startDate: '2026-08-20')])),
          organisationOpeningsRepositoryProvider.overrideWithValue(_FakeOrganisationOpeningsRepository()),
          localStorageProvider.overrideWithValue(await LocalStorage.create()),
          caregiverMessagesRepositoryProvider.overrideWithValue(_FakeCaregiverMessagesRepository()),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    // Not pumpAndSettle: the start date badge blinks via a repeating
    // AnimationController by design, so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('30000/day'), findsOneWidget);
    expect(find.text('Start: 2026-08-20'), findsOneWidget);
  });

  testWidgets('shows the start date in red, same size as the salary label, on the job card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository([_job(startDate: '2026-08-20')])),
          organisationOpeningsRepositoryProvider.overrideWithValue(_FakeOrganisationOpeningsRepository()),
          localStorageProvider.overrideWithValue(await LocalStorage.create()),
          caregiverMessagesRepositoryProvider.overrideWithValue(_FakeCaregiverMessagesRepository()),
        ],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final salaryStyle = tester.widget<Text>(find.text('30000/day')).style!;
    final startDateStyle = tester.widget<Text>(find.text('Start: 2026-08-20')).style!;
    expect(startDateStyle.color, AppColors.error);
    expect(startDateStyle.fontSize, salaryStyle.fontSize);
  });

  testWidgets('shows the salary unit as /month for a job with frequency_of_care monthly', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job(frequencyOfCare: 'monthly')]));

    expect(find.text('30000/month'), findsOneWidget);
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

    expect(find.text('Applied by you: ${_expected('2026-08-17T10:00:00Z')}'), findsOneWidget);
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

    expect(find.text('Applied by you: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined by you: ${_expected('2026-08-17T09:05:00Z')}'), findsOneWidget);
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

    expect(find.text('Applied by you: ${_expected('2026-08-15T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Accepted by employer: ${_expected('2026-08-16T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined by employer: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('You declined'), findsNothing);

    // Newest entry (Declined) sits above the oldest (Applied).
    final declinedTop = tester.getTopLeft(find.text('Declined by employer: ${_expected('2026-08-17T09:00:00Z')}')).dy;
    final appliedTop = tester.getTopLeft(find.text('Applied by you: ${_expected('2026-08-15T09:00:00Z')}')).dy;
    expect(declinedTop, lessThan(appliedTop));
  });

  testWidgets('shows the decline reason underneath the timeline when one was given', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-17T09:00:00Z',
          'accepted_at': null,
          'rejected_at': '2026-08-17T09:05:00Z',
          'decided_by_admin': true,
          'decline_reason': 'Requirement was cancelled by the patient/family.',
        }),
      ]),
    );

    expect(find.textContaining('Reason: Requirement was cancelled by the patient/family.'), findsOneWidget);
  });

  testWidgets('shows no Reason line when no decline reason was given', (tester) async {
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

    expect(find.textContaining('Reason:'), findsNothing);
  });

  testWidgets(
      'shows the same full timeline (actor, action, date/time, reason) for an organisation requirement '
      'too — not just for a regular job', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([
        _requirement(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-17T09:00:00Z',
          'accepted_at': null,
          'rejected_at': '2026-08-17T09:05:00Z',
          'decided_by_admin': true,
          'decline_reason': 'Position already filled.',
        }),
      ]),
    );
    // Rejected requirements are hidden by default (see _showAllJobs) — the
    // timeline itself is what this test is about, not that hiding rule.
    await _showAllJobs(tester);

    expect(find.text('Applied by you: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.textContaining('Declined by employer: ${_expected('2026-08-17T09:05:00Z')}'), findsOneWidget);
    expect(find.textContaining('Reason: Position already filled.'), findsOneWidget);
  });

  testWidgets('shows a Re-applied line for an organisation requirement too, after re-applying post-rejection',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([
        _requirement(myApplication: {
          'status': 'applied',
          'applied_at': '2026-08-20T09:00:00Z',
          'accepted_at': null,
          'rejected_at': null,
          'reapplied_at': '2026-08-20T09:00:00Z',
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Re-applied by you: ${_expected('2026-08-20T09:00:00Z')}'), findsOneWidget);
  });

  testWidgets('tapping Apply calls applyToJob with applied', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'applied');
  });

  testWidgets('tapping Reject shows a confirmation dialog; confirming calls applyToJob with rejected',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, isNull);
    expect(find.text('Reject this job?'), findsOneWidget);
    expect(find.text('Are you sure you want to reject the job?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'rejected');
  });

  testWidgets('cancelling the Reject confirmation dialog does not call applyToJob', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, isNull);
  });

  testWidgets('shows an empty state when there are no active jobs or organisation requirements', (tester) async {
    await _pump(tester, _FakeJobsRepository([]));

    expect(find.textContaining('No jobs posted right now'), findsOneWidget);
  });

  testWidgets('does not show the "Show All Jobs" toggle when nothing has been rejected', (tester) async {
    await _pump(tester, _FakeJobsRepository([_job()]));

    expect(find.text('Show All Jobs'), findsNothing);
  });

  testWidgets(
      'does NOT hide a job the caregiver was rejected from — it stays visible with an Apply Again button, '
      'since this list only ever contains active (re-appliable) jobs', (tester) async {
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

    expect(find.text('Show All Jobs'), findsNothing);
    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply Again'), findsOneWidget);
  });

  testWidgets(
      'does NOT hide a job the caregiver closed themselves (completed) — it stays visible with an Apply Again '
      'button — the job reopens to active for everyone else, and this caregiver can re-apply too', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'completed',
          'applied_at': '2026-08-10T09:00:00Z',
          'accepted_at': '2026-08-11T09:00:00Z',
          'rejected_at': null,
          'completed_at': '2026-08-17T09:00:00Z',
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Show All Jobs'), findsNothing);
    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply Again'), findsOneWidget);
  });

  testWidgets('tapping Apply Again on a rejected job calls applyToJob with applied, no confirmation needed',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'rejected',
        'applied_at': '2026-08-17T09:00:00Z',
        'accepted_at': null,
        'rejected_at': '2026-08-17T09:05:00Z',
        'decided_by_admin': false,
      }),
    ]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply Again'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'applied');
  });

  testWidgets('shows a Re-applied line in the timeline once reapplied_at is set', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'applied',
          'applied_at': '2026-08-18T09:00:00Z',
          'accepted_at': null,
          'rejected_at': null,
          'reapplied_at': '2026-08-18T09:00:00Z',
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Applied by you: ${_expected('2026-08-18T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Re-applied by you: ${_expected('2026-08-18T09:00:00Z')}'), findsOneWidget);
  });

  testWidgets(
      'still shows the earlier Declined entry (with reason) after the employer accepts anyway — history is '
      'no longer lost the moment status flips to accepted', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          // Now 'accepted' — but rejected_at/decline_reason from the
          // earlier decline are still present, since decide() no longer
          // clears them on a later accept.
          'status': 'accepted',
          'applied_at': '2026-08-10T09:00:00Z',
          'rejected_at': '2026-08-11T09:00:00Z',
          'decline_reason': 'Role filled internally',
          'accepted_at': '2026-08-12T09:00:00Z',
          'decided_by_admin': true,
        }),
      ]),
    );

    expect(find.text('Applied by you: ${_expected('2026-08-10T09:00:00Z')}'), findsOneWidget);
    expect(find.textContaining('Declined by employer: ${_expected('2026-08-11T09:00:00Z')}'), findsOneWidget);
    expect(find.textContaining('Reason: Role filled internally'), findsOneWidget);
    expect(find.text('Accepted by employer: ${_expected('2026-08-12T09:00:00Z')}'), findsOneWidget);
  });

  testWidgets(
      'shows all 4 entries (the full possible trail: Applied, Re-applied, Accepted, Declined) without a '
      'scrollbar — 4 rows visible by default', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-15T09:00:00Z',
          'accepted_at': '2026-08-16T09:00:00Z',
          'rejected_at': '2026-08-18T09:00:00Z',
          'reapplied_at': '2026-08-17T09:00:00Z',
          'decided_by_admin': true,
        }),
      ]),
    );

    expect(find.text('Applied by you: ${_expected('2026-08-15T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Accepted by employer: ${_expected('2026-08-16T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Re-applied by you: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined by employer: ${_expected('2026-08-18T09:00:00Z')}'), findsOneWidget);

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isFalse);
  });

  testWidgets('shows a visible, actually-scrollable thumb once a reason line pushes the trail past 4 rows',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-15T09:00:00Z',
          'accepted_at': '2026-08-16T09:00:00Z',
          'rejected_at': '2026-08-18T09:00:00Z',
          'reapplied_at': '2026-08-17T09:00:00Z',
          'decided_by_admin': true,
          'decline_reason': 'Role filled internally',
        }),
      ]),
    );

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);

    // Not just visible — actually scrollable, so the thumb isn't a
    // full-track dead end (the earlier bug: it looked scrollable but
    // nothing happened when you tried).
    final listViewFinder = find.byType(ListView).last;
    final state = tester.state<ScrollableState>(find.descendant(of: listViewFinder, matching: find.byType(Scrollable)));
    expect(state.position.maxScrollExtent, greaterThan(0));

    final oldestEntryTopBefore =
        tester.getTopLeft(find.text('Applied by you: ${_expected('2026-08-15T09:00:00Z')}')).dy;
    await tester.drag(listViewFinder, const Offset(0, -50));
    await tester.pump();
    final oldestEntryTopAfter =
        tester.getTopLeft(find.text('Applied by you: ${_expected('2026-08-15T09:00:00Z')}')).dy;
    expect(oldestEntryTopAfter, lessThan(oldestEntryTopBefore));
  });

  testWidgets('does not show a scrollbar thumb when the timeline has 3 or fewer entries', (tester) async {
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

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isFalse);
  });

  testWidgets('does not hide a job the caregiver has only applied to (not yet decided)', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'applied',
          'applied_at': '2026-08-17T09:00:00Z',
          'accepted_at': null,
          'rejected_at': null,
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.text('Show All Jobs'), findsNothing);
    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
  });

  testWidgets('hides a rejected organisation requirement by default too, revealed via Show All Jobs',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([
        _requirement(myApplication: {
          'status': 'rejected',
          'applied_at': '2026-08-17T09:00:00Z',
          'accepted_at': null,
          'rejected_at': '2026-08-17T09:05:00Z',
          'decided_by_admin': true,
        }),
      ]),
    );

    expect(find.text('ORG-JOB-7'), findsNothing);
    await _showAllJobs(tester);
    expect(find.text('ORG-JOB-7'), findsOneWidget);
  });

  testWidgets('shows a Reject Job button while still applied (not yet accepted), and confirming it withdraws',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'applied',
        'applied_at': '2026-08-17T10:00:00Z',
        'accepted_at': null,
        'rejected_at': null,
        'decided_by_admin': false,
      }),
    ]);
    await _pump(tester, fakeRepo);

    expect(find.widgetWithText(OutlinedButton, 'Reject Job'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject Job'));
    await tester.pumpAndSettle();

    expect(find.text('Reject this job?'), findsOneWidget);
    expect(find.textContaining('Are you sure you want to reject the job?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject Job'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'rejected');
  });

  testWidgets('cancelling the Reject Job confirmation dialog does not withdraw the application', (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'applied',
        'applied_at': '2026-08-17T10:00:00Z',
        'accepted_at': null,
        'rejected_at': null,
        'decided_by_admin': false,
      }),
    ]);
    await _pump(tester, fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, isNull);
  });

  testWidgets('hides both Reject Job and Apply Again once already accepted — nothing left to do until decided',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([
        _job(myApplication: {
          'status': 'accepted',
          'applied_at': '2026-08-17T10:00:00Z',
          'accepted_at': '2026-08-18T10:00:00Z',
          'rejected_at': null,
          'decided_by_admin': false,
        }),
      ]),
    );

    expect(find.widgetWithText(OutlinedButton, 'Reject Job'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Apply Again'), findsNothing);
  });

  // --- Merged organisation requirements ---

  testWidgets('shows organisation requirements alongside jobs in the same list — no separate tab', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ORG-JOB-7'), findsOneWidget);
    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('Hospital · Bangalore · Indiranagar'), findsOneWidget);
    expect(find.text('Registered Nurse'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Post-surgery wound care'), findsOneWidget);
  });

  testWidgets(
      'job and requirement cards each have a bold red border on a light green shade clearly separating them '
      'from one another — this browse list only ever shows active/live postings', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    for (final anchor in ['Job Id: ADMIN-JOB-542', 'ORG-JOB-7']) {
      final container = tester.widget<Container>(
        find.ancestor(of: find.text(anchor), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, greaterThanOrEqualTo(2.5));
      expect(border.top.color, AppColors.error);
      expect(decoration.color, AppColors.success.withValues(alpha: 0.06));
    }
  });

  testWidgets('sorts jobs and organisation requirements together by posted date, newest first', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job(postedAt: '2026-08-10T10:00:00Z')]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement(postedAt: '2026-08-15T10:00:00Z')]),
    );

    final jobCenter = tester.getCenter(find.text('Job Id: ADMIN-JOB-542'));
    final requirementCenter = tester.getCenter(find.text('ORG-JOB-7'));
    expect(requirementCenter.dy, lessThan(jobCenter.dy));
  });

  testWidgets('tapping Apply on a requirement calls the organisation repository with applied', (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository([_requirement()]);
    await _pump(tester, _FakeJobsRepository([]), orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(orgRepo.appliedWith, 'applied');
  });

  testWidgets(
      'an organisation requirement offers no Reject option at all — only Apply, unlike a regular job',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
  });

  testWidgets('the "Hospital Jobs Only" filter hides admin/individual jobs, leaving only organisation requirements',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ORG-JOB-7'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Hospital Jobs Only'));
    await tester.pumpAndSettle();

    expect(find.text('Job Id: ADMIN-JOB-542'), findsNothing);
    expect(find.text('ORG-JOB-7'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Hospital Jobs Only'));
    await tester.pumpAndSettle();

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ORG-JOB-7'), findsOneWidget);
  });

  testWidgets(
      '"Hospital Jobs Only" is styled distinctly, not just a subtle tint, so active vs inactive is unmistakable',
      (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository([_job()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_requirement()]),
    );

    final chipFinder = find.widgetWithText(FilterChip, 'Hospital Jobs Only');
    FilterChip chip() => tester.widget<FilterChip>(chipFinder);

    expect(chip().selected, isFalse);
    expect(chip().selectedColor, AppColors.primary);
    expect(chip().checkmarkColor, Colors.white);
    expect((chip().label as Text).style?.fontWeight, isNot(FontWeight.bold));

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    expect(chip().selected, isTrue);
    expect((chip().label as Text).style?.fontWeight, FontWeight.bold);
    expect((chip().label as Text).style?.color, Colors.white);
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

    expect(find.text('Applied by you: ${_expected('2026-08-17T10:00:00Z')}'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsNothing);
  });
}
