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
import 'package:nursenow_app/patient_hospital/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_state.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/individual/screens/jobs_posted_screen.dart';
import 'package:nursenow_app/patient_hospital/features/individual/widgets/caregiver_summary_card.dart' show kAcceptedGreen;
import 'package:nursenow_app/patient_hospital/features/individual/widgets/section_box.dart';
import 'package:nursenow_app/patient_hospital/features/individual/widgets/call_tap.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/patient_hospital/core/fcm/fcm_service.dart';

/// The activity log's readable time: "5 Aug 2026, 4:02 PM".
String _readableTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${months[d.month - 1]} ${d.year}, $hour12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Equivalent to pumpAndSettle(), but safe once a live (JobStatus.active)
/// requirement's status badge is on screen — its blink animation repeats
/// forever via AnimationController, so a real pumpAndSettle() never
/// observes an idle frame and times out (same reasoning as caregiver-app's
/// BlinkingStartDateBadge tests, which avoid pumpAndSettle for the same
/// reason). 500ms comfortably clears every real transition in this screen
/// (dialogs/snackbars) without completing even one blink cycle (700ms).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Patient Details and Care Preferences are collapsed by default — tap
/// the section heading to reveal the fields inside before interacting
/// with them.
Future<void> _expandSection(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await _settle(tester);
}

/// Each applicant's activity log is collapsed by default — tap every
/// "Show Activity Log" link on screen so timeline entries become visible.
/// Looping (rather than a single pass) handles multiple applicant tiles at
/// once, since each tap only reveals that one tile's own entries.
Future<void> _expandAllActivityLogs(WidgetTester tester) async {
  while (find.text('Show Activity Log').evaluate().isNotEmpty) {
    await tester.tap(find.text('Show Activity Log').first);
    await _settle(tester);
  }
}

final _scopeOfWork = ScopeOfWorkModel(
  companionCare: ['Emotional companionship', 'Meal assistance'],
  bedsideCare: ['Diaper changing & hygiene care'],
  criticalCare: ['Catheter care'],
);

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => _scopeOfWork;
}

/// Empty on purpose — this screen's own tests exercise requirement cards,
/// not the bell's unread count (see messages_bell_test.dart for that); an
/// empty template set keeps MessagesBellButton's badge out of the way of
/// this file's own text/number assertions.
class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  _FakeIndividualMessagesRepository() : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async => const [];
}

final _dutyRequirements = const DutyRequirementsModel(
  liveIn: ['Bed, bedsheet, pillow and blanket must be provided.'],
  dayDuty: ['Breakfast and lunch for the nurse.'],
  nightDuty: ['Dinner and breakfast for the nurse.'],
);

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  _FakeDutyRequirementsRepository() : super(Dio());

  @override
  Future<DutyRequirementsModel> get() async => _dutyRequirements;
}

JobModel _requirement({
  String id = 'job-1',
  int requirementNumber = 42,
  String status = 'active',
  String? salaryAmount = '1800',
  String? frequencyOfCare = 'daily',
  String? rejectionReason,
  String? cancelledAt,
  Map<String, dynamic>? careReceiver,
  List<String> languages = const ['hindi'],
}) {
  return JobModel.fromJson({
    'id': id,
    'patient_job_number': requirementNumber + 500,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Needs help with daily routine.',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'care_duration': 'few_weeks',
    'start_date': '2026-09-01',
    'languages': languages,
    'salary_amount': salaryAmount,
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'rejection_reason': rejectionReason,
    'cancelled_at': cancelledAt,
    if (careReceiver != null) 'care_receiver': careReceiver,
  });
}

final _careReceiverJson = {
  'id': 'cr-1',
  'patient_name': 'Asha Rao',
  'age': 74,
  'gender': 'female',
  'weight_kg': 58,
  'feeding_type': 'oral_feeding',
  'has_medical_condition': false,
  'medical_conditions': [],
  'toilet_assistance': ['independent'],
  'requires_vital_monitoring': false,
  'vital_monitoring_types': [],
};

JobApplicationModel _application({
  String id = 'app-1',
  String jobId = 'job-1',
  String status = 'applied',
  String fullName = 'Test Caregiver',
  String appliedAt = '2026-08-01T10:00:00Z',
  String? acceptedAt,
  String? rejectedAt,
  String? completedAt,
  String? decidedByName,
  String? declineReason,
  String? decidedBy,
  String updatedAt = '2026-08-01T10:00:00Z',
  String? reappliedAt,
  String? closeReason,
  int? agreedSalary,
  String? agreedSalaryUnit,
  String? agreedStartDate,
  Map<String, dynamic>? myFeedback,
  Map<String, dynamic>? theirFeedback,
  List<Map<String, dynamic>> agreementHistory = const [],
  double? overallRating,
}) {
  return JobApplicationModel.fromJson({
    'overall_rating': overallRating,
    'id': id,
    'job_id': jobId,
    'profile_id': 'profile-1',
    'status': status,
    'full_name': fullName,
    'phone': '+919876543210',
    'applied_at': appliedAt,
    'accepted_at': acceptedAt,
    'rejected_at': rejectedAt,
    'completed_at': completedAt,
    'decided_by_name': decidedByName,
    'decline_reason': declineReason,
    'decided_by': decidedBy,
    'updated_at': updatedAt,
    'reapplied_at': reappliedAt,
    'close_reason': closeReason ?? (status == 'completed' ? 'no_reason' : null),
    'agreed_salary': agreedSalary,
    'agreed_salary_unit': agreedSalaryUnit,
    'agreed_start_date': agreedStartDate,
    'agreement_history': agreementHistory,
    'my_feedback': myFeedback,
    'their_feedback': theirFeedback,
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  List<JobModel> requirements;
  Map<String, List<JobApplicationModel>> applicationsByJobId;
  String? decidedJobId;
  String? decidedApplicationId;
  String? decidedStatus;
  String? decidedReason;
  String? profileFetchedJobId;
  String? profileFetchedApplicationId;
  String? editedJobId;
  String? lastEditedSalaryAmount;
  String? cancelledJobId;
  String? agreementJobId;
  String? agreementApplicationId;
  int? agreementSalary;
  String? agreementUnit;
  String? agreementStartDate;
  ApiException? agreementError;
  String? madeLiveJobId;
  ApiException? makeLiveError;
  final List<List<Object?>> feedbackSent = []; // [applicationId, rating, comment]
  final List<List<Object?>> feedbackUpdated = []; // [applicationId, rating, comment]
  ApiException? feedbackError;

  _FakeIndividualRepository({this.requirements = const [], this.applicationsByJobId = const {}})
      : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async => requirements;

  @override
  Future<JobModel> editRequirement(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    String? startDate,
    required String careDuration,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    String? frequencyOfCare,
    String? salaryAmount,
  }) async {
    editedJobId = jobId;
    lastEditedSalaryAmount = salaryAmount;
    return requirements.firstWhere((r) => r.id == jobId);
  }

  @override
  Future<void> cancelRequirement(String jobId) async {
    cancelledJobId = jobId;
  }

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => applicationsByJobId[jobId] ?? const [];

  @override
  Future<void> decideApplication(String jobId, String applicationId, String status, {String? reason}) async {
    decidedJobId = jobId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
    decidedReason = reason;
  }

  @override
  Future<void> setAgreement(
    String jobId,
    String applicationId, {
    required int salary,
    required String salaryUnit,
    required String startDate,
  }) async {
    if (agreementError != null) throw agreementError!;
    agreementJobId = jobId;
    agreementApplicationId = applicationId;
    agreementSalary = salary;
    agreementUnit = salaryUnit;
    agreementStartDate = startDate;
  }

  @override
  Future<void> makeLiveAgain(String jobId) async {
    if (makeLiveError != null) throw makeLiveError!;
    madeLiveJobId = jobId;
  }

  @override
  Future<void> updateFeedback(String jobId, String applicationId, int rating, String? comment) async {
    if (feedbackError != null) throw feedbackError!;
    feedbackUpdated.add([applicationId, rating, comment]);
  }

  @override
  Future<void> submitFeedback(String jobId, String applicationId, int rating, String? comment) async {
    if (feedbackError != null) throw feedbackError!;
    feedbackSent.add([applicationId, rating, comment]);
  }

  @override

  @override

  @override
  Future<CaregiverProfileModel> getApplicantProfile(String jobId, String applicationId) async {
    profileFetchedJobId = jobId;
    profileFetchedApplicationId = applicationId;
    return CaregiverProfileModel.fromJson({
      'user_id': 'user-1',
      'profile_id': 'profile-1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'female',
      'age': 30,
      'languages': ['hindi', 'english'],
      'highest_qualification': 'rn_above_2_years',
      'religion': 'hindu',
      'terms_accepted': true,
      'verification_status': 'available',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeIndividualRepository repo, {
  bool isJobPostingBlocked = false,
  Future<bool> Function(Uri uri)? phoneLauncher,
  // Rejected candidates are collapsed behind one row; most tests want to see them, so open it.
  bool expandRejected = true,
  Widget? home,
}) async {
  // Requirement cards accumulate a lot of content (About Patient/Requirement
  // tags, Edit/Cancel/Post Similar actions, applicant review section) — tall
  // enough that the default 800x600 test viewport clips action buttons out
  // of hit-testable range for some fixtures. A generous default surface
  // avoids that for every test in this file, not just the ones that
  // happened to need it first.
  await tester.binding.setSurfaceSize(const Size(360, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        if (phoneLauncher != null) phoneLauncherProvider.overrideWithValue(phoneLauncher),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
        individualMessagesRepositoryProvider.overrideWithValue(_FakeIndividualMessagesRepository()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()), FcmService(IndividualRepository(Dio()), OrganisationRepository(Dio())))
            ..state = SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
            ),
        ),
      ],
      child: MaterialApp(home: home ?? const JobsPostedScreen()),
    ),
  );
  await _settle(tester);
  if (home == null && expandRejected && find.byKey(const Key('rejected-toggle')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('rejected-toggle')));
    await _settle(tester);
  }
}

void main() {
  testWidgets("the patient's requirement card no longer has a Preferred Start Date field", (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    expect(find.textContaining('Preferred Start Date'), findsNothing);
    expect(find.textContaining('start date'), findsNothing);
  });

  testWidgets('shows an empty state with no posting CTA when there are no requirements yet', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    expect(find.textContaining("don't have any requirements posted yet"), findsOneWidget);
    // There is no "Post a Requirement" action anywhere on this screen any
    // more — posting only ever happens once, as part of registration
    // itself. A brand-new account with zero requirements has no way to
    // post one from here (nor anywhere else in the app).
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
  });

  testWidgets('never shows a posting CTA regardless of requirement status — closed, rejected, pending, or active',
      (tester) async {
    for (final status in ['closed', 'pending_review', 'active']) {
      await _pump(
        tester,
        _FakeIndividualRepository(requirements: [_requirement(status: status, salaryAmount: null, frequencyOfCare: null)]),
      );
      expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
    }
  });

  testWidgets('shows every requirement in history directly — no toggle, nothing hidden', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-2', requirementNumber: 43, status: 'active'),
          _requirement(id: 'job-1', requirementNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
      ),
    );

    expect(find.textContaining('Show Closed/Cancelled Requirements'), findsNothing);
    expect(find.text('Job Id: PAT-JOB-543'), findsOneWidget);
    expect(find.text('Job Id: PAT-JOB-542'), findsOneWidget);
  });

  testWidgets(
      'shows the accepted caregiver on a closed requirement up front, not just while active — an accepted candidate keeps it out of the closed/cancelled section',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    // No toggle needed — visible immediately, same as a live requirement.
    expect(find.textContaining('Show Closed/Cancelled Requirements'), findsNothing);
    expect(find.text('Closed — caregiver assigned'), findsOneWidget);
    expect(find.text('1 candidate applied in total'), findsOneWidget);
    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets(
      'a live (active) requirement card has a wide red border on a light green background — senior-citizen-friendly visibility, a calm medical look',
      (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, greaterThanOrEqualTo(2.5));
    expect(border.top.color, AppColors.error);
    expect(decoration.color, kMedicalGreenCard);
  });

  testWidgets('a closed requirement card has a grey border, not red — it is no longer live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      ),
    );

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final border = (container.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.textSecondary);
  });

  testWidgets('a cancelled requirement card has a grey border, not red', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
      ),
    );

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final border = (container.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.textSecondary);
  });

  testWidgets('a pending_review requirement card has a grey border — not yet live/visible to caregivers',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)],
      ),
    );

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final border = (container.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.textSecondary);
  });

  testWidgets(
      'Patient Details and Care Preferences are collapsed by default — tapping each heading reveals its '
      'pre-filled fields', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    // Old flat "Show Full Details" toggle is gone — replaced by two
    // independently collapsible sections, each starting collapsed.
    expect(find.text('Show Full Details'), findsNothing);
    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    expect(find.widgetWithText(TextField, '74'), findsNothing);

    await _expandSection(tester, 'Patient Details');
    expect(find.widgetWithText(TextField, '74'), findsOneWidget);

    // Salary is shown via the always-visible summary line outside both
    // collapsible sections, so it's visible even before Care Preferences
    // is expanded.
    expect(find.text('1800'), findsOneWidget);
  });

  testWidgets('shows the pre-filled Salary field directly for a pending_review requirement too — '
      'no longer gated behind admin approval', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review')]),
    );

    expect(find.text('1800'), findsOneWidget);
  });

  testWidgets(
      'shows a Type Of Care line and a Scope Of Work link whenever a care receiver is present, and the '
      'popup shows the derived tier — same as what a caregiver sees on the same job in NurseJobs', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    // _careReceiverJson has no medical condition/toilet-assistance/feeding
    // needs, so it derives to the baseline Companion Care tier.
    expect(find.text('Type Of Care: Companion Care'), findsOneWidget);
    // Visible up front — not gated behind "Show Full Details".
    expect(find.text('What You Get'), findsOneWidget);

    await tester.tap(find.text('What You Get'));
    await _settle(tester);

    expect(find.text('Companion Care'), findsWidgets);
    expect(find.text('Emotional companionship'), findsOneWidget);
    expect(find.text('Diaper changing & hygiene care'), findsNothing);
  });

  testWidgets('does not show a Type Of Care line or Scope Of Work link when the requirement has no care receiver yet',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement()]),
    );

    expect(find.textContaining('Type Of Care'), findsNothing);
    expect(find.text('What You Get'), findsNothing);
  });

  testWidgets('shows Job Id and a Duty Requirements link on every card', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    expect(find.text('Job Id: PAT-JOB-542'), findsOneWidget);
    expect(find.text('What You Provide'), findsOneWidget);

    await tester.tap(find.text('What You Provide'));
    await _settle(tester);

    // "24Hrs - Live In" also appears as the card's own pre-filled "Hours
    // Care Needed" dropdown value — scope to the dialog specifically.
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('24Hrs - Live In')),
      findsOneWidget,
    );
  });

  testWidgets('with multiple applicants and nobody accepted yet, every candidate is shown, each with Accept/Reject',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(id: 'app-1', fullName: 'Ramesh Kumar', appliedAt: '2026-08-01T10:00:00Z'),
            _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
          ],
        },
      ),
    );

    expect(find.text('2 candidates applied in total'), findsOneWidget);
    expect(find.text('2 candidates awaiting your decision'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('Sita Devi'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Reject'), findsNWidgets(2));
  });

  testWidgets(
      "each candidate's activity log is collapsed by default, expands independently on tap, and collapses again",
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(id: 'app-1', fullName: 'Ramesh Kumar', appliedAt: '2026-08-01T10:00:00Z'),
            _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
          ],
        },
      ),
    );

    // Collapsed by default — a "Show Activity Log" link per candidate, no
    // raw "Applied: <date>" text visible yet for either one.
    expect(find.text('Show Activity Log'), findsNWidgets(2));
    expect(find.textContaining('Applied:'), findsNothing);

    // Expanding Ramesh's log reveals only his entry — Sita's stays
    // collapsed, proving each tile tracks its own state independently.
    await tester.tap(find.text('Show Activity Log').first);
    await _settle(tester);

    expect(find.text('Show Activity Log'), findsOneWidget);
    expect(find.text('Hide Activity Log'), findsOneWidget);
    expect(find.textContaining('Applied:'), findsOneWidget);

    // Tapping it again collapses it back.
    await tester.tap(find.text('Hide Activity Log'));
    await _settle(tester);

    expect(find.text('Show Activity Log'), findsNWidgets(2));
    expect(find.textContaining('Applied:'), findsNothing);
  });

  testWidgets('shows a Re-applied line for a candidate under review who previously rejected/closed this job',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(appliedAt: '2026-08-05T10:00:00Z', reappliedAt: '2026-08-05T10:00:00Z'),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    final expected = DateTime.parse('2026-08-05T10:00:00Z').toLocal();
    expect(
      find.text(
        'Re-applied: ${_readableTime(expected)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows no Re-applied line for a first-time applicant', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application()],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Re-applied:'), findsNothing);
  });

  testWidgets('a candidate awaiting a decision is highlighted with an amber border and an hourglass icon',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application()],
        },
      ),
    );

    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    final tile = tester.widget<Container>(
      find.ancestor(of: find.byIcon(Icons.hourglass_top), matching: find.byType(Container)).first,
    );
    final decoration = tile.decoration as BoxDecoration;
    expect((decoration.border as Border).top.color, AppColors.warning);
  });

  testWidgets('an accepted candidate shows a green check icon', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    // white check on the solid green accepted card
    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(icon.color, Colors.white);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });

  testWidgets('a rejected candidate shows a red cross icon', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit', decidedBy: 'individual-1')],
        },
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.cancel));
    expect(icon.color, AppColors.error);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets(
      'with a caregiver accepted, another candidate who applied can still be accepted or declined, '
      'and the accepted one can be rejected', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(id: 'app-1', fullName: 'Ramesh Kumar', status: 'accepted', appliedAt: '2026-08-01T10:00:00Z'),
            _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
          ],
        },
      ),
    );

    expect(find.text('2 candidates applied in total'), findsOneWidget);
    // No explanatory banner: the status pill and the menu say it.
    expect(find.textContaining('You have accepted a'), findsNothing);
    expect(find.text('1 candidate awaiting your decision'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('Sita Devi'), findsOneWidget);
    // Sita (still applied) offers Accept and Reject; Ramesh (accepted) offers only Reject.
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reject'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsNWidgets(2));
  });

  testWidgets('a second caregiver can be accepted while the first stays accepted (no one-at-a-time rule)',
      (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [
          _application(id: 'app-1', fullName: 'Ramesh Kumar', status: 'accepted'),
          _application(id: 'app-2', fullName: 'Sita Devi'),
        ],
      },
    );
    await _pump(tester, repo);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await _settle(tester);
    expect(repo.decidedApplicationId, 'app-2');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('rejecting an already-accepted candidate undoes the acceptance, via the same mandatory-reason flow',
      (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [
          _application(id: 'app-1', fullName: 'Ramesh Kumar', status: 'accepted', appliedAt: '2026-08-01T10:00:00Z'),
          _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
        ],
      },
    );
    await _pump(tester, repo);

    // Precondition: both candidates are visible, with only one Reject
    // button (the accepted candidate's undo action).
    expect(find.text('+919876543210'), findsNWidgets(2));
    expect(find.text('Sita Devi'), findsOneWidget);

    // The accepted candidate is listed first; Sita (applied) also has a Reject button.
    await tester.tap(find.widgetWithText(FilledButton, 'Reject').first);
    await _settle(tester);

    expect(find.text('Decline this candidate'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Changed our mind');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await _settle(tester);

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Changed our mind');
  });

  testWidgets('a candidate previously rejected can still be accepted, labeled "Accept Anyway"', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application(status: 'rejected', declineReason: 'Not a fit', decidedBy: 'individual-1')],
      },
    );
    await _pump(tester, repo);

    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsOneWidget);
    // A candidate already decided (rejected) can't be rejected again.
    expect(find.widgetWithText(FilledButton, 'Reject'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept Anyway'));
    await _settle(tester);

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets(
      'a candidate the caregiver self-withdrew from (rejected by caregiver) can still be accepted by the patient',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected')], // decidedBy omitted — self-withdrawal
        },
      ),
    );

    expect(find.text('Rejected by Caregiver'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsOneWidget);
  });

  testWidgets(
      'a completed engagement (caregiver closed the job themselves) offers View Profile and an "Accept Anyway" '
      'option, but not Reject', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'completed')],
        },
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reject'), findsNothing);
  });

  testWidgets('tapping "Accept Anyway" on a completed engagement calls decideApplication with accepted', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [_application(id: 'app-1', status: 'completed')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept Anyway'));
    await _settle(tester);

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('accepting an applicant calls decideApplication with the right job and application id', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await _settle(tester);

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('tapping View Profile on the candidate under review opens their full profile', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
    expect(find.text('Registered Nurse above 2 years of experience'), findsOneWidget);
    // The "VitaCare-verified caregiver" badge was removed from the
    // product entirely.
    expect(find.text('VitaCare-verified caregiver'), findsNothing);
  });

  testWidgets('View Profile stays available for an accepted candidate', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application(status: 'accepted')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('rejecting requires a reason — Confirm stays disabled until something is typed', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await _settle(tester);

    expect(find.text('Decline this candidate'), findsOneWidget);
    var confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Schedule does not match');
    await tester.pump();
    confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await _settle(tester);

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Schedule does not match');
  });

  testWidgets('cancelling the reject dialog does not call the repository', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);

    expect(repo.decidedApplicationId, isNull);
  });

  testWidgets('a decided/rejected applicant shows the reason underneath in the read-only history', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(
              status: 'rejected',
              declineReason: 'Not available on weekends',
              rejectedAt: '2026-08-05T14:32:00Z',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Reason: Not available on weekends'), findsOneWidget);
  });

  testWidgets('still shows a rejected candidate\'s phone number — they can always be reconsidered', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(status: 'rejected', declineReason: 'Not a fit', rejectedAt: '2026-08-05T14:32:00Z'),
          ],
        },
      ),
    );

    expect(find.text('+919876543210'), findsOneWidget);
  });

  testWidgets('still shows an accepted candidate\'s phone number', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    expect(find.text('+919876543210'), findsOneWidget);
  });

  testWidgets('shows the full timeline — applied then accepted, naming who accepted — for an accepted candidate',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(
              status: 'accepted',
              appliedAt: '2026-08-04T09:00:00Z',
              acceptedAt: '2026-08-05T09:00:00Z',
              decidedByName: 'Asha Patel',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Applied:'), findsOneWidget);
    expect(find.textContaining('Accepted by Asha Patel:'), findsOneWidget);

    // Newest first — the most recent action (Accepted) renders above the
    // older one (Applied), not the other way round.
    final acceptedTop = tester.getTopLeft(find.textContaining('Accepted by Asha Patel:')).dy;
    final appliedTop = tester.getTopLeft(find.textContaining('Applied:')).dy;
    expect(acceptedTop, lessThan(appliedTop));
  });

  testWidgets(
      'still shows the earlier Rejected entry (with reason) after accepting anyway — history is no longer '
      'lost the moment status flips to accepted', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(
              status: 'accepted',
              appliedAt: '2026-08-01T09:00:00Z',
              rejectedAt: '2026-08-02T09:00:00Z',
              declineReason: 'Not a fit',
              decidedByName: 'Asha Patel',
              acceptedAt: '2026-08-03T09:00:00Z',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Applied:'), findsOneWidget);
    expect(find.textContaining('Rejected by Asha Patel:'), findsOneWidget);
    expect(find.textContaining('Reason: Not a fit'), findsOneWidget);
    expect(find.textContaining('Accepted by Asha Patel:'), findsOneWidget);
  });

  testWidgets('shows "Rejected by Caregiver" and still shows the phone when the caregiver closed the job themselves '
      'before being accepted', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          // decidedBy omitted — self-withdrawal.
          'job-1': [_application(status: 'rejected', rejectedAt: '2026-08-05T14:32:00Z')],
        },
      ),
    );

    expect(find.text('Rejected by Caregiver'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    // Full detail: exactly when the caregiver rejected it, not just the label.
    await _expandAllActivityLogs(tester);
    final expected = DateTime.parse('2026-08-05T14:32:00Z').toLocal();
    expect(
      find.text(
        'Rejected by Caregiver: ${_readableTime(expected)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows plain "Rejected" (not "by Caregiver") when the patient was the one who declined them',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(
              status: 'rejected',
              declineReason: 'Not a fit',
              decidedBy: 'individual-1',
              decidedByName: 'Asha Patel',
              rejectedAt: '2026-08-05T14:32:00Z',
            ),
          ],
        },
      ),
    );

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Rejected by Caregiver'), findsNothing);
    // The timeline names exactly who decided, not just "by Caregiver".
    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Rejected by Asha Patel:'), findsOneWidget);
  });

  testWidgets('shows "Closed by Caregiver" and still keeps the phone number for a completed engagement',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(status: 'completed', fullName: 'Ramesh Kumar', completedAt: '2026-08-06T09:05:00Z'),
          ],
        },
      ),
    );

    expect(find.text('Closed by Caregiver'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    // Defaults to "No Reason" in the timeline when the fixture doesn't
    // specify one — same default the backend applies.
    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Reason: No Reason'), findsOneWidget);
  });

  testWidgets('shows a specific close reason in the timeline when the caregiver picked one', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(
              status: 'completed',
              fullName: 'Ramesh Kumar',
              completedAt: '2026-08-06T09:05:00Z',
              closeReason: 'need_to_go_hometown',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Reason: Need to Go to Hometown'), findsOneWidget);
  });

  testWidgets('the More options menu offers only Cancel — there is no Edit action (fields are editable on the card itself)',
      (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Edit the Job'), findsNothing);
    expect(find.text('Post Similar Requirement'), findsNothing);
    expect(find.text('Cancel the Job'), findsOneWidget);
  });

  testWidgets('fields are always editable, even with an active application — no lock any more', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(careReceiver: _careReceiverJson)],
        applicationsByJobId: {
          'job-1': [_application(status: 'applied')],
        },
      ),
    );
    await _expandSection(tester, 'Patient Details');

    expect(find.textContaining('Editing is locked'), findsNothing);
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
  });

  testWidgets('the tick/cross Save/Discard controls are hidden until a field actually changes', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );
    await _expandSection(tester, 'Patient Details');

    expect(find.byKey(const Key('area-save')), findsNothing);
    expect(find.byKey(const Key('area-discard')), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();

    expect(find.byKey(const Key('area-save')), findsOneWidget);
    expect(find.byKey(const Key('area-discard')), findsOneWidget);
  });

  testWidgets('tapping the cross button discards the edit and hides the controls again', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );
    await _expandSection(tester, 'Patient Details');

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    await tester.tap(find.byKey(const Key('area-discard')));
    await _settle(tester);

    expect(find.byKey(const Key('area-save')), findsNothing);
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.controller!.text, 'Indiranagar');
  });

  testWidgets(
      'controls appear independently per field, not just one pair for the whole card — and discarding one field '
      'leaves another field\'s pending edit untouched', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );
    await _expandSection(tester, 'Patient Details');

    expect(find.byKey(const Key('area-save')), findsNothing);
    expect(find.byKey(const Key('age-save')), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '80');
    await tester.pump();

    // Both fields' own controls appear, independently.
    expect(find.byKey(const Key('area-save')), findsOneWidget);
    expect(find.byKey(const Key('age-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('area-discard')));
    await _settle(tester);

    // Area reverted and its controls are gone...
    expect(find.byKey(const Key('area-save')), findsNothing);
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.controller!.text, 'Indiranagar');
    // ...but the still-pending Age edit is untouched.
    expect(find.byKey(const Key('age-save')), findsOneWidget);
    final ageField = tester.widget<TextField>(find.widgetWithText(TextField, "Patient's Age (Mandatory)"));
    expect(ageField.controller!.text, '80');
  });

  testWidgets('editing the Area field and tapping the tick calls editRequirement with the updated value '
      '— no confirmation needed when there is no active application', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]);
    await _pump(tester, repo);
    await _expandSection(tester, 'Patient Details');

    final ageField = tester.widget<TextField>(find.widgetWithText(TextField, "Patient's Age (Mandatory)"));
    expect(ageField.controller!.text, '74');
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.controller!.text, 'Indiranagar');

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('area-save')));
    await tester.tap(find.byKey(const Key('area-save')));
    await _settle(tester);

    expect(find.text('Modify this requirement?'), findsNothing);
    expect(repo.editedJobId, 'job-1');
  });

  testWidgets(
      'Salary is deliberately read-only — never a TextField, no tick/cross controls of its own, '
      'only ever auto-derived from the Rate Card suggestion', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextField, 'Salary (₹/day) (Negotiable)'), findsNothing);
    expect(find.text('1800'), findsOneWidget);
    expect(find.byKey(const Key('salary-save')), findsNothing);
    expect(find.byKey(const Key('salary-discard')), findsNothing);

    // Editing an unrelated field never produces salary-specific controls
    // either — only that field's own tick/cross pair appears.
    await _expandSection(tester, 'Patient Details');
    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    expect(find.byKey(const Key('area-save')), findsOneWidget);
    expect(find.byKey(const Key('salary-save')), findsNothing);
  });

  testWidgets(
      'editing a field with an active application shows a confirmation dialog before saving, and does nothing if declined',
      (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(careReceiver: _careReceiverJson)],
      applicationsByJobId: {
        'job-1': [_application(status: 'applied')],
      },
    );
    await _pump(tester, repo);
    await _expandSection(tester, 'Patient Details');

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('area-save')));
    await tester.tap(find.byKey(const Key('area-save')));
    await _settle(tester);

    expect(find.text('Modify this requirement?'), findsOneWidget);
    expect(find.textContaining('discussing any changes with the candidates directly'), findsOneWidget);
    expect(repo.editedJobId, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'No, keep it as is'));
    await _settle(tester);

    expect(repo.editedJobId, isNull);
    expect(find.byKey(const Key('area-save')), findsOneWidget); // edit is still pending, not discarded
  });

  testWidgets('confirming the active-application warning proceeds with the save', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(careReceiver: _careReceiverJson)],
      applicationsByJobId: {
        'job-1': [_application(status: 'applied')],
      },
    );
    await _pump(tester, repo);
    await _expandSection(tester, 'Patient Details');

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('area-save')));
    await tester.tap(find.byKey(const Key('area-save')));
    await _settle(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Yes, modify'));
    await _settle(tester);

    expect(repo.editedJobId, 'job-1');
  });

  testWidgets('rejected/completed applications do not trigger the active-application confirmation', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', careReceiver: _careReceiverJson)],
      applicationsByJobId: {
        'job-1': [_application(status: 'rejected', declineReason: 'Not a fit')],
      },
    );
    await _pump(tester, repo);
    await _expandSection(tester, 'Patient Details');

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Koramangala');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('area-save')));
    await tester.tap(find.byKey(const Key('area-save')));
    await _settle(tester);

    expect(find.text('Modify this requirement?'), findsNothing);
    expect(repo.editedJobId, 'job-1');
  });

  testWidgets('Cancel the Job is enabled on a live requirement, and confirming it calls cancelRequirement', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Cancel the Job'), findsOneWidget);
    expect(find.text('Make it live again'), findsNothing);
    await tester.tap(find.text('Cancel the Job'));
    await _settle(tester);

    // The warning says exactly what happens to whom.
    expect(find.text('Cancel this job?'), findsOneWidget);
    expect(find.textContaining('Candidates who applied but are not accepted will be rejected'), findsOneWidget);
    expect(find.textContaining('Caregivers you have already accepted stay accepted'), findsOneWidget);
    expect(find.textContaining('make the job live again at any time'), findsOneWidget);
    expect(repo.cancelledJobId, isNull);
    await tester.tap(find.text('Yes, cancel it'));
    await _settle(tester);

    expect(repo.cancelledJobId, 'job-1');
  });

  testWidgets('cancelling the cancel-requirement confirmation dialog does not call cancelRequirement', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Cancel the Job'));
    await _settle(tester);
    await tester.tap(find.text('No, keep it'));
    await _settle(tester);

    expect(repo.cancelledJobId, isNull);
  });

  testWidgets('a cancelled job shows Cancelled, keeps its candidates visible, and offers Make it live again (no Cancel)', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
        applicationsByJobId: {
          'job-1': [_application(id: 'a1', status: 'rejected', fullName: 'Ramesh Kumar', decidedBy: 'someone', declineReason: 'This requirement was cancelled.')],
        },
        // (rejected candidates are collapsed; the tests' helper opens the row)
      ),
    );

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.textContaining('candidate applied in total'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Make it live again'), findsOneWidget);
    expect(find.text('Cancel the Job'), findsNothing);
    expect(find.text('Make Active Again'), findsNothing);
  });

  testWidgets('Make it live again on a cancelled job confirms, then calls make-live (nobody is rejected)', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Make it live again'));
    await _settle(tester);
    expect(find.text('Make it live again?'), findsOneWidget);
    expect(find.textContaining('Candidates who were rejected when you cancelled can apply again.'), findsOneWidget);
    await tester.tap(find.text('Make it live'));
    await _settle(tester);

    expect(repo.madeLiveJobId, 'job-1');
    expect(repo.decidedStatus, isNull);
  });

  testWidgets('shows the server error message if making the job live fails', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
    )..makeLiveError = const ApiException(code: 'JOB_010', message: 'Posting is blocked on your account');
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Make it live again'));
    await _settle(tester);
    await tester.tap(find.text('Make it live'));
    await _settle(tester);

    expect(find.text('Posting is blocked on your account'), findsOneWidget);
    // showVitaErrorBanner auto-dismisses after 5s — flush that timer so it
    // doesn't leak past this test.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Cancel the Job is disabled once the requirement was admin-rejected', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, rejectionReason: 'Duplicate posting'),
        ],
      ),
    );

    expect(find.text('Rejected'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Cancel the Job (Unavailable)'), findsOneWidget);
  });


  group('agreed salary and start date', () {
    testWidgets('an accepted caregiver with nothing agreed yet shows an "Enter salary and start date" button',
        (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
        ),
      );
      expect(find.text('Enter salary and start date'), findsOneWidget);
    });

    testWidgets('a caregiver with no salary yet shows "Salary not set yet" and the add button in their own card', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
        ),
      );
      final card = find.byKey(const Key('caregiver-card-app-1'));
      expect(find.descendant(of: card, matching: find.text('Salary not set yet')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('card-add-agreement-app-1'))), findsOneWidget);
    });
    testWidgets('an accepted caregiver with an agreement shows it in the job\'s own unit (per day for a daily job)',
        (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed', frequencyOfCare: 'daily')],
          applicationsByJobId: {
            'job-1': [_application(status: 'accepted', agreedSalary: 800, agreedStartDate: '2026-11-20')],
          },
        ),
      );
      expect(find.text('₹800 per day'), findsOneWidget);
      expect(find.textContaining('20 Nov 2026'), findsOneWidget);
      expect(find.text('Enter salary and start date'), findsNothing);
    });

    testWidgets("the patient's own unit choice wins over the job's frequency", (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed', frequencyOfCare: 'daily')],
          applicationsByJobId: {
            'job-1': [
              _application(status: 'accepted', agreedSalary: 24000, agreedSalaryUnit: 'monthly', agreedStartDate: '2026-11-20'),
            ],
          },
        ),
      );
      expect(find.text('₹24,000 per month'), findsOneWidget);
    });

    testWidgets('the popup offers Per day / Per month, preselecting the job\'s own frequency', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed', frequencyOfCare: 'monthly')],
          applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
        ),
      );
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);

      expect(find.text('Per day'), findsOneWidget);
      expect(find.text('Per month'), findsOneWidget);
      expect(find.text('Agreed Salary (₹ per month)'), findsOneWidget);
    });

    testWidgets('switching to Per day changes the label and is what gets saved', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', frequencyOfCare: 'monthly')],
        applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);

      await tester.tap(find.text('Per day'));
      await _settle(tester);
      expect(find.text('Agreed Salary (₹ per day)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '900');
      await tester.tap(find.text('Select a date'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.tap(find.text('Save & send to caregiver'));
      await _settle(tester);

      expect(repo.agreementUnit, 'daily');
      expect(repo.agreementSalary, 900);
    });

    testWidgets('a monthly job shows the agreed salary per month', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed', frequencyOfCare: 'monthly')],
          applicationsByJobId: {
            'job-1': [_application(status: 'accepted', agreedSalary: 24000, agreedStartDate: '2026-11-20')],
          },
        ),
      );
      expect(find.text('₹24,000 per month'), findsOneWidget);
    });

    testWidgets('tapping the add button opens the popup with the care-staff message and both fields',
        (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
        ),
      );
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);

      expect(find.text('Confirm salary and start date'), findsOneWidget);
      expect(find.textContaining('care staff, not house maids'), findsOneWidget);
      expect(find.textContaining('treated the way you treat your own family members'), findsOneWidget);
      expect(find.text('Agreed Salary (₹ per day)'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('Fill later'), findsOneWidget);
    });

    testWidgets('Save with empty fields flags both and sends nothing', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);
      await tester.tap(find.text('Save & send to caregiver'));
      await _settle(tester);

      expect(find.text('Enter the agreed salary in rupees'), findsOneWidget);
      expect(find.text('Pick the start date'), findsOneWidget);
      expect(repo.agreementSalary, isNull);
      expect(find.text('Confirm salary and start date'), findsOneWidget);
    });

    testWidgets('Fill later closes the popup without saving', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);
      await tester.tap(find.text('Fill later'));
      await _settle(tester);

      expect(find.text('Confirm salary and start date'), findsNothing);
      expect(repo.agreementSalary, isNull);
      expect(find.text('Enter salary and start date'), findsOneWidget);
    });

    testWidgets('saving sends the salary and the picked date for that caregiver', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
      );
      await _pump(tester, repo);
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), '900');
      await tester.tap(find.text('Select a date'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.tap(find.text('Save & send to caregiver'));
      await _settle(tester);

      expect(repo.agreementJobId, 'job-1');
      expect(repo.agreementApplicationId, 'app-1');
      expect(repo.agreementSalary, 900);
      expect(repo.agreementStartDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(find.text('Confirm salary and start date'), findsNothing);
      expect(find.text('Sent to Test Caregiver.'), findsOneWidget);
    });

    testWidgets('a server error is shown inside the popup and it stays open', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {'job-1': [_application(status: 'accepted')]},
      )..agreementError = const ApiException(message: 'The start date cannot be in the past', code: 'JOB_023');
      await _pump(tester, repo);
      await tester.tap(find.text('Enter salary and start date'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '900');
      await tester.tap(find.text('Select a date'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.tap(find.text('Save & send to caregiver'));
      await _settle(tester);

      expect(find.text('The start date cannot be in the past'), findsOneWidget);
      expect(find.text('Confirm salary and start date'), findsOneWidget);
    });

    testWidgets('accepting a candidate opens the popup right away', (tester) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {'job-1': [_application(status: 'applied')]},
      );
      await _pump(tester, repo);
      // The fake does not change the stored status, so make the next load report it accepted.
      repo.applicationsByJobId = {'job-1': [_application(status: 'accepted')]};
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await _settle(tester);

      expect(repo.decidedStatus, 'accepted');
      expect(find.text('Confirm salary and start date'), findsOneWidget);
    });
  });


  group('calling the caregiver from the applicant tile', () {
    _FakeIndividualRepository repoWith(String status) => _FakeIndividualRepository(
          requirements: [_requirement(status: status == 'applied' ? 'active' : 'closed')],
          applicationsByJobId: {'job-1': [_application(status: status, fullName: 'Ramesh Kumar')]},
        );

    testWidgets("tapping a candidate's name opens their profile (not the dialer)", (tester) async {
      final launched = <Uri>[];
      final repo = repoWith('applied');
      await _pump(tester, repo, phoneLauncher: (uri) async {
        launched.add(uri);
        return true;
      });
      await tester.tap(find.byKey(const Key('applicant-name-app-1')));
      await _settle(tester);
      expect(repo.profileFetchedJobId, 'job-1');
      expect(repo.profileFetchedApplicationId, 'app-1');
      expect(launched, isEmpty);
    });

    testWidgets("tapping an accepted caregiver's name opens their profile, without folding the card", (tester) async {
      final repo = repoWith('accepted');
      await _pump(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('caregiver-name-app-1')));
      await tester.tap(find.byKey(const Key('caregiver-name-app-1')));
      await _settle(tester);
      expect(repo.profileFetchedApplicationId, 'app-1');
    });

    testWidgets("a rejected candidate's name also opens their profile", (tester) async {
      final repo = repoWith('rejected');
      await _pump(tester, repo, expandRejected: true);
      await tester.tap(find.byKey(const Key('applicant-name-app-1')));
      await _settle(tester);
      expect(repo.profileFetchedApplicationId, 'app-1');
    });

    testWidgets("tapping the caregiver's number opens the dialer with their number", (tester) async {
      final launched = <Uri>[];
      await _pump(tester, repoWith('accepted'), phoneLauncher: (uri) async {
        launched.add(uri);
        return true;
      });
      await tester.tap(find.text('+919876543210'));
      await _settle(tester);
      expect(launched.single.toString(), 'tel:+919876543210');
    });

    testWidgets('the number is visibly tappable: a call icon sits beside it', (tester) async {
      await _pump(tester, repoWith('applied'));
      expect(find.descendant(of: find.byType(CallTap), matching: find.byIcon(Icons.call)), findsOneWidget);
    });

    testWidgets('a rejected candidate can still be called, the number stays visible', (tester) async {
      final launched = <Uri>[];
      await _pump(tester, repoWith('rejected'), phoneLauncher: (uri) async {
        launched.add(uri);
        return true;
      });
      await tester.tap(find.text('+919876543210'));
      await _settle(tester);
      expect(launched, hasLength(1));
    });

    testWidgets('if the phone cannot open the dialer, a banner shows the number to dial by hand', (tester) async {
      await _pump(tester, repoWith('applied'), phoneLauncher: (uri) async => false);
      await tester.tap(find.text('+919876543210'));
      await _settle(tester);
      expect(find.text('Could not open the dialer. Call +919876543210 directly.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // the banner's own 5s timer
    });

    testWidgets('a launcher that throws is handled the same way', (tester) async {
      await _pump(tester, repoWith('applied'), phoneLauncher: (uri) async => throw Exception('no dialer'));
      await tester.tap(find.text('+919876543210'));
      await _settle(tester);
      expect(find.text('Could not open the dialer. Call +919876543210 directly.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // the banner's own 5s timer
    });

    testWidgets("tapping the name does not accept or reject the candidate", (tester) async {
      final repo = repoWith('applied');
      await _pump(tester, repo, phoneLauncher: (uri) async => true);
      await tester.tap(find.text('+919876543210'));
      await _settle(tester);
      expect(repo.decidedStatus, isNull);
    });
  });


  group('the caregiver\'s overall rating as stars in an arc over her picture', () {
    _FakeIndividualRepository repoWith(List<JobApplicationModel> apps, {String status = 'active'}) => _FakeIndividualRepository(
          requirements: [_requirement(status: status)],
          applicationsByJobId: {'job-1': apps},
        );

    testWidgets('an accepted caregiver\'s card shows the arc', (tester) async {
      await _pump(
        tester,
        repoWith([_application(id: 'a1', status: 'accepted', fullName: 'Asha', acceptedAt: '2026-11-01T10:00:00Z', overallRating: 4.5)], status: 'closed'),
      );
      final card = find.byKey(const Key('caregiver-card-a1'));
      expect(find.descendant(of: card, matching: find.byKey(const Key('rating-arc-avatar'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byIcon(Icons.star)), findsNWidgets(4));
      expect(find.descendant(of: card, matching: find.byIcon(Icons.star_half)), findsOneWidget);
    });

    testWidgets('a waiting candidate\'s tile shows the arc too, so she is recognisable at a glance', (tester) async {
      await _pump(tester, repoWith([_application(id: 'w1', status: 'applied', fullName: 'Ramesh', overallRating: 5)]));
      expect(find.byKey(const Key('rating-arc-avatar')), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(5));
    });

    testWidgets('an unrated caregiver has no arc, on the card or the tile', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a1', status: 'accepted', fullName: 'Asha', acceptedAt: '2026-11-01T10:00:00Z'),
          _application(id: 'w1', status: 'applied', fullName: 'Ramesh'),
        ]),
      );
      expect(find.byKey(const Key('rating-arc-avatar')), findsNothing);
    });
  });

  group('candidate tile spacing', () {
    testWidgets('name, phone, activity log and profile button have clear gaps between them', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {'job-1': [_application(id: 'r1', status: 'rejected', fullName: 'Ramesh Rejected', decidedBy: 'someone')]},
        ),
        expandRejected: true,
      );
      final name = tester.getRect(find.byKey(const Key('applicant-name-r1')));
      final phone = tester.getRect(find.byKey(const Key('call-button')));
      final log = tester.getRect(find.text('Show Activity Log'));
      final profile = tester.getRect(find.widgetWithText(OutlinedButton, 'View Profile'));
      expect(phone.top - name.bottom, greaterThanOrEqualTo(12), reason: 'name -> phone');
      expect(log.top - phone.bottom, greaterThanOrEqualTo(12), reason: 'phone -> activity log');
      expect(profile.top - log.bottom, greaterThanOrEqualTo(12), reason: 'activity log -> profile');
    });
  });

  group('rejected candidates are collapsed until tapped', () {
    _FakeIndividualRepository repoWith(List<JobApplicationModel> applications, {String status = 'active'}) =>
        _FakeIndividualRepository(
          requirements: [_requirement(status: status)],
          applicationsByJobId: {'job-1': applications},
        );

    testWidgets('a rejected candidate is hidden behind one row, with a count', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a1', status: 'applied', fullName: 'Ramesh Kumar'),
          _application(id: 'a2', status: 'rejected', fullName: 'Sita Devi', decidedBy: 'someone'),
        ]),
        expandRejected: false,
      );
      expect(find.text('Rejected candidates (1)'), findsOneWidget);
      expect(find.text('Sita Devi'), findsNothing);
      expect(find.text('Ramesh Kumar'), findsOneWidget);
    });

    testWidgets('the total still counts everyone, rejected included', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a1', status: 'applied', fullName: 'Ramesh Kumar'),
          _application(id: 'a2', status: 'rejected', fullName: 'Sita Devi', decidedBy: 'someone'),
        ]),
        expandRejected: false,
      );
      expect(find.text('2 candidates applied in total'), findsOneWidget);
    });

    testWidgets('tapping the row shows the rejected candidate with phone and View Profile, and tapping again hides them',
        (tester) async {
      await _pump(
        tester,
        repoWith([_application(id: 'a2', status: 'rejected', fullName: 'Sita Devi', decidedBy: 'someone')]),
        expandRejected: false,
      );
      await tester.tap(find.byKey(const Key('rejected-toggle')));
      await _settle(tester);
      expect(find.text('Sita Devi'), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsOneWidget);

      await tester.tap(find.byKey(const Key('rejected-toggle')));
      await _settle(tester);
      expect(find.text('Sita Devi'), findsNothing);
    });

    testWidgets('an applied or accepted candidate is never collapsed', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a1', status: 'accepted', fullName: 'Asha Accepted'),
          _application(id: 'a3', status: 'applied', fullName: 'Ramesh Applied'),
        ]),
        expandRejected: false,
      );
      expect(find.text('Asha Accepted'), findsOneWidget);
      expect(find.text('Ramesh Applied'), findsOneWidget);
      expect(find.byKey(const Key('rejected-toggle')), findsNothing);
    });

    testWidgets('a candidate who closed the job themselves (completed) stays visible, not collapsed', (tester) async {
      await _pump(
        tester,
        repoWith([_application(id: 'a4', status: 'completed', fullName: 'Closed Caregiver')]),
        expandRejected: false,
      );
      expect(find.text('Closed Caregiver'), findsOneWidget);
      expect(find.byKey(const Key('rejected-toggle')), findsNothing);
    });

    testWidgets('no collapsed row when nobody was rejected', (tester) async {
      await _pump(tester, repoWith([_application(status: 'applied')]), expandRejected: false);
      expect(find.byKey(const Key('rejected-toggle')), findsNothing);
    });

    testWidgets('the row counts every rejected candidate', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a2', status: 'rejected', fullName: 'Sita Devi', decidedBy: 'x'),
          _application(id: 'a5', status: 'rejected', fullName: 'Meena Rao'),
        ]),
        expandRejected: false,
      );
      expect(find.text('Rejected candidates (2)'), findsOneWidget);
    });

    testWidgets('an accepted candidate stays on top while the rejected ones are tucked away', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'a2', status: 'rejected', fullName: 'Sita Devi', decidedBy: 'x'),
          _application(id: 'a1', status: 'accepted', fullName: 'Asha Accepted'),
        ], status: 'closed'),
        expandRejected: false,
      );
      expect(find.text('Asha Accepted'), findsOneWidget);
      expect(find.text('Sita Devi'), findsNothing);
      expect(find.text('Rejected candidates (1)'), findsOneWidget);
    });
  });

  group('Cancel the job and Make it live again (accepted caregivers are never rejected)', () {
    _FakeIndividualRepository repo({
      String status = 'closed',
      String? cancelledAt,
      String? rejectionReason,
      List<JobApplicationModel>? apps,
    }) =>
        _FakeIndividualRepository(
          requirements: [_requirement(status: status, cancelledAt: cancelledAt, rejectionReason: rejectionReason)],
          applicationsByJobId: {
            'job-1': apps ?? [_application(id: 'app-9', status: 'accepted', fullName: 'Asha Accepted')],
          },
        );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);
    }

    testWidgets('a job closed by an acceptance offers both Make it live again and Cancel the Job', (tester) async {
      await _pump(tester, repo());
      await openMenu(tester);
      expect(find.text('Make it live again'), findsOneWidget);
      expect(find.text('Cancel the Job'), findsOneWidget);
      expect(find.text('Permanently cancel'), findsNothing);
    });

    testWidgets('a live job (even with a caregiver already accepted) offers only Cancel the Job', (tester) async {
      await _pump(tester, repo(status: 'active'));
      await openMenu(tester);
      expect(find.text('Cancel the Job'), findsOneWidget);
      expect(find.text('Make it live again'), findsNothing);
    });

    testWidgets('a job still in admin review can be cancelled, and cannot be made live', (tester) async {
      await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review')]));
      await openMenu(tester);
      expect(find.text('Cancel the Job'), findsOneWidget);
      expect(find.text('Make it live again'), findsNothing);
    });

    testWidgets('a cancelled job can be made live again but not cancelled again', (tester) async {
      await _pump(tester, repo(cancelledAt: '2026-11-17T10:00:00Z'));
      await openMenu(tester);
      expect(find.text('Make it live again'), findsOneWidget);
      expect(find.text('Cancel the Job'), findsNothing);
    });

    testWidgets('Make it live again confirms, and says nobody already accepted is rejected', (tester) async {
      final r = repo();
      await _pump(tester, r);
      await openMenu(tester);
      await tester.tap(find.text('Make it live again'));
      await _settle(tester);
      expect(find.text('Make it live again?'), findsOneWidget);
      expect(find.textContaining('Caregivers you have already accepted stay accepted.'), findsOneWidget);
      expect(r.madeLiveJobId, isNull);

      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(r.madeLiveJobId, isNull);
    });

    testWidgets('confirming makes the job live again WITHOUT rejecting the accepted caregiver', (tester) async {
      final r = repo();
      await _pump(tester, r);
      await openMenu(tester);
      await tester.tap(find.text('Make it live again'));
      await _settle(tester);
      await tester.tap(find.text('Make it live'));
      await _settle(tester);
      expect(r.madeLiveJobId, 'job-1');
      expect(r.decidedStatus, isNull);
      expect(r.cancelledJobId, isNull);
      expect(find.text('The job is live again.'), findsOneWidget);
    });

    testWidgets('Cancel the Job on a job with an accepted caregiver warns that waiting candidates are rejected but the accepted stay', (tester) async {
      final r = repo(apps: [
        _application(id: 'app-9', status: 'accepted', fullName: 'Asha Accepted'),
        _application(id: 'app-3', status: 'applied', fullName: 'Ramesh Applied'),
      ]);
      await _pump(tester, r);
      await openMenu(tester);
      await tester.tap(find.text('Cancel the Job'));
      await _settle(tester);
      expect(find.text('Cancel this job?'), findsOneWidget);
      expect(find.textContaining('Candidates who applied but are not accepted will be rejected'), findsOneWidget);
      expect(find.textContaining('Caregivers you have already accepted stay accepted'), findsOneWidget);
      await tester.tap(find.text('Yes, cancel it'));
      await _settle(tester);
      expect(r.cancelledJobId, 'job-1');
      expect(r.decidedStatus, isNull); // the app never rejects anyone itself; the server rejects only the waiting ones
    });

    testWidgets('a cancelled job with an accepted caregiver says so, keeps the caregiver visible, and still offers Accept Anyway on the candidates the cancel rejected', (tester) async {
      await _pump(
        tester,
        repo(cancelledAt: '2026-11-17T10:00:00Z', apps: [
          _application(id: 'app-9', status: 'accepted', fullName: 'Asha Accepted'),
          _application(id: 'app-3', status: 'rejected', fullName: 'Ramesh Rejected', decidedBy: 'someone', declineReason: 'This requirement was cancelled.'),
        ]),
      );
      expect(find.text('Cancelled — caregiver assigned'), findsOneWidget);
      expect(find.text('Asha Accepted'), findsOneWidget);
      expect(find.byKey(const Key('caregiver-card-app-9')), findsOneWidget);
      // a candidate rejected by the cancel can still be accepted ("Accept Anyway"), as always
      expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsOneWidget);
    });

    for (final cancelledAt in [null, '2026-11-17T10:00:00Z']) {
      testWidgets('every rejected candidate has Accept Anyway (job ${cancelledAt == null ? 'live' : 'cancelled'})', (tester) async {
        await _pump(
          tester,
          repo(status: cancelledAt == null ? 'active' : 'closed', cancelledAt: cancelledAt, apps: [
            _application(id: 'r1', status: 'rejected', fullName: 'Ramesh Rejected', decidedBy: 'someone'),
            _application(id: 'r2', status: 'rejected', fullName: 'Sita Rejected', decidedBy: 'someone'),
          ]),
        );
        expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsNWidgets(2));
      });
    }

    testWidgets('an admin-rejected requirement can be neither cancelled nor made live by the patient', (tester) async {
      await _pump(tester, repo(rejectionReason: 'Duplicate posting', apps: [_application(status: 'accepted')]));
      await openMenu(tester);
      expect(find.text('Make it live again'), findsNothing);
      expect(find.text('Cancel the Job'), findsNothing);
      expect(find.text('Cancel the Job (Unavailable)'), findsOneWidget);
    });

    testWidgets('a live job with a caregiver accepted lets more candidates be accepted, with no banner', (tester) async {
      await _pump(
        tester,
        repo(status: 'active', apps: [
          _application(id: 'app-9', status: 'accepted', fullName: 'Asha Accepted'),
          _application(id: 'app-3', status: 'applied', fullName: 'Ramesh Applied'),
        ]),
      );
      expect(find.textContaining('Your job is live'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    });
  });

  group('several accepted caregivers, each with their own salary and start date', () {
    String iso(int days) {
      final d = DateTime.now().add(Duration(days: days));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    _FakeIndividualRepository twoCaregivers() => _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {
            'job-1': [
              // Asha: daily 1000, accepted second
              _application(id: 'a1', status: 'accepted', fullName: 'Asha Rao', acceptedAt: '2026-11-03T10:00:00Z',
                  agreedSalary: 1000, agreedSalaryUnit: 'daily', agreedStartDate: iso(-2)),
              // Meena: monthly 30000, accepted first
              _application(id: 'a2', status: 'accepted', fullName: 'Meena Das', acceptedAt: '2026-11-01T10:00:00Z',
                  agreedSalary: 30000, agreedSalaryUnit: 'monthly', agreedStartDate: iso(-10)),
              // Ravi: accepted, no salary yet
              _application(id: 'a3', status: 'accepted', fullName: 'Ravi Kumar'),
              // Sita is only a candidate waiting
              _application(id: 'a4', status: 'applied', fullName: 'Sita Waiting'),
            ],
          },
        );

    testWidgets('accepted caregivers are part of the candidates list: one card each, under the total', (tester) async {
      await _pump(tester, twoCaregivers());
      expect(find.text('4 candidates applied in total'), findsOneWidget);
      expect(find.byKey(const Key('caregiver-card-a1')), findsOneWidget);
      expect(find.byKey(const Key('caregiver-card-a2')), findsOneWidget);
      expect(find.byKey(const Key('caregiver-card-a3')), findsOneWidget);
      expect(find.byKey(const Key('caregiver-card-a4')), findsNothing);
    });

    testWidgets('each card shows that caregiver\'s own salary, unit and start date', (tester) async {
      await _pump(tester, twoCaregivers());
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a1')), matching: find.text('₹1,000 per day')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a2')), matching: find.text('₹30,000 per month')), findsOneWidget);
      expect(find.byKey(const Key('card-start-a1')), findsOneWidget);
      expect(find.byKey(const Key('card-start-a2')), findsOneWidget);
    });

    testWidgets('there is no salary-due box, leave or "Salary & leaves" on a card any more', (tester) async {
      await _pump(tester, twoCaregivers());
      expect(find.byKey(const Key('next-salary')), findsNothing);
      expect(find.byKey(const Key('card-leave-tag')), findsNothing);
      expect(find.textContaining('Salary & leaves'), findsNothing);
      expect(find.byKey(const Key('salary-due-banner')), findsNothing);
    });

    testWidgets('the earliest accepted caregiver is first, and one with no salary yet shows how to add it', (tester) async {
      await _pump(tester, twoCaregivers());
      final meena = tester.getTopLeft(find.byKey(const Key('caregiver-card-a2'))).dy;
      final asha = tester.getTopLeft(find.byKey(const Key('caregiver-card-a1'))).dy;
      final ravi = tester.getTopLeft(find.byKey(const Key('caregiver-card-a3'))).dy;
      expect(meena, lessThan(asha));
      expect(asha, lessThan(ravi));
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a3')), matching: find.text('Salary not set yet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a3')), matching: find.text('Enter salary and start date')), findsOneWidget);
    });

    testWidgets('one button, "Enter salary and start date", opens the popup with both fields', (tester) async {
      await _pump(tester, twoCaregivers());
      await tester.ensureVisible(find.byKey(const Key('card-add-agreement-a3')));
      await tester.tap(find.byKey(const Key('card-add-agreement-a3')));
      await _settle(tester);
      expect(find.text('Confirm salary and start date'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.textContaining('Agreed Salary'), findsOneWidget);
    });

    testWidgets('a caregiver who already has one gets "Edit salary and start date": the popup opens filled in and saves the change', (tester) async {
      final repo = twoCaregivers();
      await _pump(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('card-edit-agreement-a1')));
      await tester.tap(find.byKey(const Key('card-edit-agreement-a1')));
      await _settle(tester);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '1000');
      await tester.enterText(find.byType(TextField), '1200');
      await tester.tap(find.text('Save & send to caregiver'));
      await _settle(tester);
      expect(repo.agreementApplicationId, 'a1');
      expect(repo.agreementSalary, 1200);
    });

    testWidgets('Agreed salary, the amount and the start date sit on one line', (tester) async {
      await _pump(tester, twoCaregivers());
      final line = find.byKey(const Key('card-agreement-line-a1'));
      expect(line, findsOneWidget);
      final salaryY = tester.getCenter(find.byKey(const Key('card-salary-a1'))).dy;
      final startY = tester.getCenter(find.byKey(const Key('card-start-a1'))).dy;
      final labelY = tester.getCenter(find.descendant(of: line, matching: find.text('Agreed salary:'))).dy;
      expect((salaryY - startY).abs(), lessThan(8));
      expect((salaryY - labelY).abs(), lessThan(8));
      double size(Finder f) => tester.widget<Text>(f).style!.fontSize!;
      final label = find.descendant(of: line, matching: find.text('Agreed salary:'));
      expect(size(label), size(find.byKey(const Key('card-salary-a1'))));
      expect(size(find.byKey(const Key('card-start-a1'))), size(find.byKey(const Key('card-salary-a1'))));
    });

    testWidgets('every accepted caregiver card starts unfolded, showing its details', (tester) async {
      await _pump(tester, twoCaregivers());
      for (final id in ['a1', 'a2', 'a3']) {
        expect(find.byKey(Key('caregiver-card-chevron-$id')), findsOneWidget);
        expect(tester.widget<Icon>(find.byKey(Key('caregiver-card-chevron-$id'))).icon, Icons.expand_less);
      }
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a1')), matching: find.text('₹1,000 per day')), findsOneWidget);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsOneWidget);
    });

    testWidgets('tapping a caregiver\'s header folds the whole card down to just their name, and tapping again unfolds it', (tester) async {
      await _pump(tester, twoCaregivers());
      await tester.ensureVisible(find.byKey(const Key('caregiver-card-chevron-a1')));
      await tester.tap(find.byKey(const Key('caregiver-card-chevron-a1')));
      await _settle(tester);

      final card = find.byKey(const Key('caregiver-card-a1'));
      // the name (and the Accepted label) stay on the folded item
      expect(find.descendant(of: card, matching: find.text('Asha Rao')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Accepted')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const Key('caregiver-card-chevron-a1'))).icon, Icons.expand_more);
      // everything else is folded away: phone, salary, buttons, activity log, feedback
      expect(find.descendant(of: card, matching: find.text('₹1,000 per day')), findsNothing);
      expect(find.descendant(of: card, matching: find.byKey(const Key('call-button'))), findsNothing);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('Reject')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('View Profile')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('Show Activity Log')), findsNothing);

      await tester.tap(find.byKey(const Key('caregiver-card-chevron-a1')));
      await _settle(tester);
      expect(find.descendant(of: card, matching: find.text('₹1,000 per day')), findsOneWidget);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const Key('caregiver-card-chevron-a1'))).icon, Icons.expand_less);
    });

    testWidgets('each caregiver folds independently: folding one leaves the others open', (tester) async {
      await _pump(tester, twoCaregivers());
      await tester.ensureVisible(find.byKey(const Key('caregiver-card-chevron-a1')));
      await tester.tap(find.byKey(const Key('caregiver-card-chevron-a1')));
      await _settle(tester);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsNothing);
      // Meena (a2) is untouched and still shows everything
      expect(find.descendant(of: find.byKey(const Key('caregiver-card-a2')), matching: find.text('₹30,000 per month')), findsOneWidget);
      expect(find.byKey(const Key('card-edit-agreement-a2')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const Key('caregiver-card-chevron-a2'))).icon, Icons.expand_less);

      // folding a second one doesn't reopen the first
      await tester.ensureVisible(find.byKey(const Key('caregiver-card-chevron-a2')));
      await tester.tap(find.byKey(const Key('caregiver-card-chevron-a2')));
      await _settle(tester);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsNothing);
      expect(find.byKey(const Key('card-edit-agreement-a2')), findsNothing);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Meena Das'), findsOneWidget);
    });

    testWidgets('a folded card stays folded after the list reloads (for example after a decision elsewhere)', (tester) async {
      final repo = twoCaregivers();
      await _pump(tester, repo);
      await tester.ensureVisible(find.byKey(const Key('caregiver-card-chevron-a1')));
      await tester.tap(find.byKey(const Key('caregiver-card-chevron-a1')));
      await _settle(tester);
      // pull to refresh
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await _settle(tester);
      expect(find.byKey(const Key('card-edit-agreement-a1')), findsNothing);
    });

    testWidgets('accepted caregivers come first in the list, then the candidates still waiting', (tester) async {
      await _pump(tester, twoCaregivers());
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Sita Waiting'), findsOneWidget);
      final lastAccepted = tester.getTopLeft(find.byKey(const Key('caregiver-card-a3'))).dy;
      final waiting = tester.getTopLeft(find.text('Sita Waiting')).dy;
      expect(lastAccepted, lessThan(waiting));
    });
  });

  group('WhatsApp next to the caregiver phone number', () {
    testWidgets('the accepted caregiver card and a waiting candidate both have a WhatsApp chip', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {
            'job-1': [
              _application(id: 'a1', status: 'accepted', fullName: 'Asha Rao'),
              _application(id: 'a2', status: 'applied', fullName: 'Ramesh Kumar'),
            ],
          },
        ),
      );
      expect(find.byKey(const Key('whatsapp-tap')), findsNWidgets(2));
      expect(find.byKey(const Key('whatsapp-glyph')), findsNWidgets(2));
    });

    testWidgets('tapping it opens a WhatsApp chat with that caregiver', (tester) async {
      final launched = <Uri>[];
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {'job-1': [_application(status: 'applied', fullName: 'Ramesh Kumar')]},
        ),
        phoneLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      await tester.tap(find.byKey(const Key('whatsapp-tap')));
      await _settle(tester);
      expect(launched.single.toString(), 'https://wa.me/919876543210');
    });

  });


  group('feedback about a caregiver', () {
    String iso(int offset) {
      final d = DateTime.now().add(Duration(days: offset));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    JobApplicationModel accepted({int startOffset = -3, String? acceptedAt = '2026-11-01T10:00:00Z', Map<String, dynamic>? mine, Map<String, dynamic>? theirs}) =>
        _application(
          id: 'app-1',
          status: 'accepted',
          fullName: 'Asha Accepted',
          acceptedAt: acceptedAt,
          agreedSalary: 1000,
          agreedSalaryUnit: 'daily',
          agreedStartDate: iso(startOffset),
          myFeedback: mine,
          theirFeedback: theirs,
        );

    Future<_FakeIndividualRepository> open(WidgetTester tester, JobApplicationModel application) async {
      final repo = _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {'job-1': [application]},
      );
      await _pump(tester, repo);
      return repo;
    }

    testWidgets('once the start date has arrived the accepted caregiver has a "Rate this caregiver" button', (tester) async {
      await open(tester, accepted());
      expect(find.byKey(const Key('leave-feedback')), findsOneWidget);
      expect(find.text('Rate this caregiver'), findsOneWidget);
    });

    testWidgets('before the work has started there is no button', (tester) async {
      await open(tester, accepted(startOffset: 3));
      expect(find.byKey(const Key('leave-feedback')), findsNothing);
      expect(find.byKey(const Key('feedback-section')), findsNothing);
    });

    testWidgets('with no agreed start date yet there is no button', (tester) async {
      await open(
        tester,
        _application(id: 'app-1', status: 'accepted', fullName: 'Asha Accepted', acceptedAt: '2026-11-01T10:00:00Z'),
      );
      expect(find.byKey(const Key('leave-feedback')), findsNothing);
    });

    testWidgets('rating sends the stars and comment, and thanks the patient', (tester) async {
      final repo = await open(tester, accepted());
      await tester.tap(find.byKey(const Key('leave-feedback')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('feedback-comment')), 'Gentle and reliable');
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await _settle(tester);
      expect(repo.feedbackSent.single, ['app-1', 5, 'Gentle and reliable']);
      expect(find.text('Thank you for your feedback.'), findsOneWidget);
    });

    testWidgets('once written, the card shows only the patient\'s own feedback', (tester) async {
      await open(tester, accepted(mine: {'rating': 4, 'comment': 'Good'}));
      expect(find.byKey(const Key('leave-feedback')), findsNothing);
      expect(find.byKey(const Key('feedback-mine')), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.byKey(const Key('feedback-received')), findsNothing);
    });

    testWidgets('what the caregiver wrote about the patient is never shown to the patient, even if it were sent', (tester) async {
      await open(
        tester,
        accepted(mine: {'rating': 4, 'comment': 'Good'}, theirs: {'rating': 1, 'comment': 'Private note about the family'}),
      );
      expect(find.byKey(const Key('feedback-received')), findsNothing);
      expect(find.text('Private note about the family'), findsNothing);
      expect(find.text('Feedback about you'), findsNothing);
    });

    testWidgets('with no feedback written by the patient, a caregiver\'s feedback does not show up either', (tester) async {
      await open(tester, accepted(theirs: {'rating': 2, 'comment': 'Private note about the family'}));
      expect(find.byKey(const Key('feedback-received')), findsNothing);
      expect(find.text('Private note about the family'), findsNothing);
      // the patient can still rate the caregiver
      expect(find.byKey(const Key('leave-feedback')), findsOneWidget);
    });

    testWidgets('a server refusal is shown in the sheet', (tester) async {
      final repo = await open(tester, accepted());
      repo.feedbackError = const ApiException(message: 'You can leave feedback once the work has started', code: 'FEEDBACK_001');
      await tester.tap(find.byKey(const Key('leave-feedback')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('feedback-star-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await _settle(tester);
      expect(find.text('You can leave feedback once the work has started'), findsOneWidget);
      expect(repo.feedbackSent, isEmpty);
    });

  });

  group('inviting a friend', () {
    testWidgets('once a candidate has applied, a small "Share JustHeal" card appears under the requirement', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {'job-1': [_application(status: 'applied')]},
        ),
      );
      expect(find.byKey(const Key('share-app-card')), findsOneWidget);
      expect(find.byKey(const Key('share-app-whatsapp')), findsOneWidget);
    });

    testWidgets('before anyone has applied there is no prompt', (tester) async {
      await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));
      expect(find.byKey(const Key('share-app-card')), findsNothing);
    });

    testWidgets('after sending feedback, the thank-you offers a one-tap "Share JustHeal"', (tester) async {
      final requirement = _requirement(status: 'closed');
      final repo = _FakeIndividualRepository(
        requirements: [requirement],
        applicationsByJobId: {
          'job-1': [
            _application(
              id: 'app-1',
              status: 'accepted',
              fullName: 'Asha Accepted',
              acceptedAt: '2026-11-01T10:00:00Z',
              agreedSalary: 1000,
              agreedSalaryUnit: 'daily',
              agreedStartDate: '2026-11-10',
            ),
          ],
        },
      );
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('leave-feedback')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await _settle(tester);
      expect(find.text('Thank you for your feedback.'), findsOneWidget);
      expect(find.text('Share JustHeal'), findsOneWidget);
    });

    group('changing the feedback you left', () {
      JobApplicationModel withFeedback() => _application(
            id: 'app-1',
            status: 'accepted',
            fullName: 'Asha Accepted',
            acceptedAt: '2026-11-01T10:00:00Z',
            agreedSalary: 1000,
            agreedSalaryUnit: 'daily',
            agreedStartDate: '2026-11-10',
            myFeedback: {'rating': 3, 'comment': 'Ok'},
          );

      Future<_FakeIndividualRepository> open(WidgetTester tester) async {
        final repo = _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [withFeedback()]},
        );
        await _pump(tester, repo);
        return repo;
      }

      testWidgets('your feedback has an Edit button, and the sheet opens filled in', (tester) async {
        await open(tester);
        expect(find.byKey(const Key('edit-feedback')), findsOneWidget);
        await tester.tap(find.byKey(const Key('edit-feedback')));
        await _settle(tester);
        expect(find.text('Your feedback for Asha Accepted'), findsOneWidget);
        expect(find.text('Save changes'), findsOneWidget);
        expect(tester.widget<TextField>(find.byKey(const Key('feedback-comment'))).controller!.text, 'Ok');
        expect(find.byIcon(Icons.star), findsNWidgets(3 + 3)); // 3 stars in the sheet, 3 in "Your feedback" behind it
      });

      testWidgets('saving sends the change through the update call, not a second send', (tester) async {
        final repo = await open(tester);
        await tester.tap(find.byKey(const Key('edit-feedback')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('feedback-star-5')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('feedback-comment')), 'Much better now');
        await tester.tap(find.byKey(const Key('feedback-submit')));
        await _settle(tester);
        expect(repo.feedbackUpdated.single, ['app-1', 5, 'Much better now']);
        expect(repo.feedbackSent, isEmpty);
        expect(find.text('Your feedback was updated.'), findsOneWidget);
      });

      testWidgets('cancelling the edit changes nothing', (tester) async {
        final repo = await open(tester);
        await tester.tap(find.byKey(const Key('edit-feedback')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('feedback-cancel')));
        await _settle(tester);
        expect(repo.feedbackUpdated, isEmpty);
      });

      testWidgets('a server error stays in the sheet', (tester) async {
        final repo = await open(tester);
        repo.feedbackError = const ApiException(message: 'There is no feedback of yours to change yet', code: 'FEEDBACK_003');
        await tester.tap(find.byKey(const Key('edit-feedback')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('feedback-submit')));
        await _settle(tester);
        expect(find.text('There is no feedback of yours to change yet'), findsOneWidget);
        expect(repo.feedbackUpdated, isEmpty);
      });

      testWidgets('the first-time sheet tells the family they can change it later', (tester) async {
        final repo = _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {
            'job-1': [
              _application(
                id: 'app-1',
                status: 'accepted',
                fullName: 'Asha Accepted',
                acceptedAt: '2026-11-01T10:00:00Z',
                agreedSalary: 1000,
                agreedSalaryUnit: 'daily',
                agreedStartDate: '2026-11-10',
              ),
            ],
          },
        );
        await _pump(tester, repo);
        await tester.tap(find.byKey(const Key('leave-feedback')));
        await _settle(tester);
        expect(find.textContaining('You can change it later.'), findsOneWidget);
      });
    });
  });

  group('light green requirement card and red rejected row', () {
    Color? fillOf(WidgetTester tester, Finder f) => ((tester.widget<Container>(f)).decoration as BoxDecoration).color;

    testWidgets('the whole requirement rectangle, and the Patient Details / Care Preferences boxes, are light green', (tester) async {
      await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active', careReceiver: _careReceiverJson)]));
      final card = find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first;
      expect(fillOf(tester, card), kMedicalGreenCard);
      for (final title in ['Patient Details', 'Care Preferences']) {
        final box = find.ancestor(of: find.text(title), matching: find.byType(Container)).first;
        expect(fillOf(tester, box), kMedicalGreenSection, reason: title);
      }
      // a light green, not white or grey: green is the strongest channel
      final c = kMedicalGreenCard;
      expect(c.g, greaterThan(c.r));
      expect(c.g, greaterThan(c.b));
    });

    testWidgets('the card stays light green when the job is cancelled or closed', (tester) async {
      await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'closed', cancelledAt: '2026-11-17T10:00:00Z')]));
      final card = find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first;
      expect(fillOf(tester, card), kMedicalGreenCard);
    });

    testWidgets('the "Rejected candidates" row is the same red tint as a rejected candidate\'s tile', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {
            'job-1': [_application(id: 'r1', status: 'rejected', fullName: 'Ramesh Rejected', decidedBy: 'someone')],
          },
        ),
        expandRejected: false,
      );
      final row = find.descendant(of: find.byKey(const Key('rejected-toggle')), matching: find.byType(Container)).first;
      final decoration = tester.widget<Container>(row).decoration as BoxDecoration;
      expect(decoration.color, AppColors.error.withValues(alpha: 0.1));
      // its label and chevron use the red too
      final label = tester.widget<Text>(find.text('Rejected candidates (1)'));
      expect(label.style!.color, AppColors.error);
    });
  });

  group('colours: accepted is green, rejected is red', () {
    Color? backgroundOf(WidgetTester tester, Finder f) {
      final box = tester.widget<Container>(f);
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('an accepted caregiver\'s card is a solid green, a little lighter than the Rate Card button, with white text', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [_application(id: 'a1', status: 'accepted', fullName: 'Asha Accepted')]},
        ),
      );
      expect(backgroundOf(tester, find.byKey(const Key('caregiver-card-a1'))), kAcceptedGreen);
      // lighter than the Rate Card green, but still a green (not washed out)
      expect(kAcceptedGreen.computeLuminance(), greaterThan(AppColors.success.computeLuminance()));
      expect(kAcceptedGreen.g, greaterThan(kAcceptedGreen.r));
      expect(kAcceptedGreen.g, greaterThan(kAcceptedGreen.b));
      // white text on it: the name and the salary/start lines
      final card = find.byKey(const Key('caregiver-card-a1'));
      expect(tester.widget<Text>(find.descendant(of: card, matching: find.text('Asha Accepted'))).style!.color, Colors.white);
      expect(tester.widget<Text>(find.descendant(of: card, matching: find.text('Accepted'))).style!.color, Colors.white);
    });

    testWidgets('a rejected candidate\'s tile is tinted with the red of the Reject button', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {
            'job-1': [_application(id: 'r1', status: 'rejected', fullName: 'Ramesh Rejected', decidedBy: 'someone')],
          },
        ),
      );
      final tile = find.ancestor(of: find.text('Ramesh Rejected'), matching: find.byType(Container)).first;
      // the closest container with a tint is the tile itself
      final tinted = find
          .ancestor(of: find.text('Ramesh Rejected'), matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .contains(AppColors.error.withValues(alpha: 0.1));
      expect(tile, findsOneWidget);
      expect(tinted, isTrue);
    });

    testWidgets('Reject is white on red everywhere, the counterpart of Accept (and Accept Anyway) being white on green', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {
            'job-1': [
              _application(id: 'acc', status: 'accepted', fullName: 'Asha Accepted'),
              _application(id: 'app', status: 'applied', fullName: 'Ramesh Applied'),
              _application(id: 'rej', status: 'rejected', fullName: 'Sita Rejected', decidedBy: 'someone'),
            ],
          },
        ),
      );
      Color? bg(Finder f) => tester.widget<FilledButton>(f).style!.backgroundColor!.resolve({});
      Color? fg(Finder f) => tester.widget<FilledButton>(f).style!.foregroundColor!.resolve({});
      // Reject on the accepted caregiver's card and on the still-waiting candidate's tile
      final rejects = find.widgetWithText(FilledButton, 'Reject');
      expect(rejects, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(bg(rejects.at(i)), AppColors.error);
        expect(fg(rejects.at(i)), Colors.white);
      }
      // Accept and Accept Anyway: white on green
      for (final label in ['Accept', 'Accept Anyway']) {
        final f = find.widgetWithText(FilledButton, label);
        expect(f, findsOneWidget, reason: label);
        expect(bg(f), AppColors.success);
        expect(fg(f), Colors.white);
      }
    });

    testWidgets('(old check) on the green card the Reject button is red with white text', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [_application(id: 'a1', status: 'accepted', fullName: 'Asha Accepted')]},
        ),
      );
      final reject = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reject'));
      expect(reject.style!.backgroundColor!.resolve({}), AppColors.error);
      expect(reject.style!.foregroundColor!.resolve({}), Colors.white);
    });

    testWidgets('a candidate still waiting keeps its own amber, not red or green', (tester) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'active')],
          applicationsByJobId: {'job-1': [_application(id: 'w1', status: 'applied', fullName: 'Sita Waiting')]},
        ),
      );
      final colours = find
          .ancestor(of: find.text('Sita Waiting'), matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .toList();
      expect(colours, isNot(contains(AppColors.error.withValues(alpha: 0.1))));
      expect(colours, isNot(contains(AppColors.success.withValues(alpha: 0.1))));
    });
  });

  group('the activity log records every salary / start date change', () {
    JobApplicationModel withHistory(List<Map<String, dynamic>> history) => _application(
          id: 'a1',
          status: 'accepted',
          fullName: 'Asha Accepted',
          acceptedAt: '2026-11-01T10:00:00Z',
          agreedSalary: 1200,
          agreedSalaryUnit: 'daily',
          agreedStartDate: '2026-11-26',
          agreementHistory: history,
        );

    Future<void> openLog(WidgetTester tester, JobApplicationModel application) async {
      await _pump(
        tester,
        _FakeIndividualRepository(
          requirements: [_requirement(status: 'closed')],
          applicationsByJobId: {'job-1': [application]},
        ),
      );
      await tester.ensureVisible(find.text('Show Activity Log'));
      await tester.tap(find.text('Show Activity Log'));
      await _settle(tester);
    }

    testWidgets('the first entry reads "entered", later ones "changed", each with its amount and start date, newest first', (tester) async {
      await openLog(tester, withHistory([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1100, 'unit': 'daily', 'start_date': '2026-11-20', 'at': '2026-11-19T09:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      expect(find.textContaining('Salary and start date entered'), findsOneWidget);
      expect(find.textContaining('Salary and start date changed'), findsNWidgets(2));
      expect(find.textContaining('₹30,000 per month, starts 1 Nov 2026'), findsOneWidget);
      expect(find.textContaining('₹1,100 per day, starts 20 Nov 2026'), findsOneWidget);
      expect(find.textContaining('₹1,200 per day, starts 26 Nov 2026'), findsOneWidget);
      final newest = tester.getTopLeft(find.textContaining('₹1,200 per day, starts')).dy;
      final oldest = tester.getTopLeft(find.textContaining('₹30,000 per month, starts')).dy;
      expect(newest, lessThan(oldest));
    });

    testWidgets('a very light separator sits between every two entries of the log, and not before the first or after the last', (tester) async {
      await openLog(tester, withHistory([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      // applied + accepted + two salary entries = 4 entries -> 3 separators
      for (final i in [1, 2, 3]) {
        expect(find.byKey(Key('log-separator-$i')), findsOneWidget, reason: 'separator $i');
      }
      expect(find.byKey(const Key('log-separator-0')), findsNothing);
      expect(find.byKey(const Key('log-separator-4')), findsNothing);
      final divider = tester.widget<Divider>(find.byKey(const Key('log-separator-1')));
      expect(divider.thickness, lessThanOrEqualTo(0.5));
      expect(divider.color!.a, lessThan(0.5)); // faint, not a heavy rule
    });

    testWidgets('two entries have one separator between them', (tester) async {
      await openLog(tester, withHistory(const [])); // applied + accepted
      expect(find.byKey(const Key('log-separator-1')), findsOneWidget);
      expect(find.byKey(const Key('log-separator-2')), findsNothing);
    });

    testWidgets('it sits alongside the other events (accepted, etc.), ordered by time', (tester) async {
      await openLog(tester, withHistory([
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      expect(find.textContaining('Accepted'), findsWidgets);
      expect(find.textContaining('Salary and start date entered'), findsOneWidget);
    });

    testWidgets('with no history there is no salary line in the log', (tester) async {
      await openLog(tester, withHistory(const []));
      expect(find.textContaining('Salary and start date'), findsNothing);
    });
  });
}
