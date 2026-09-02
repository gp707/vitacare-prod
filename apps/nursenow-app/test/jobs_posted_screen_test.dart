import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/core/duty_requirements/duty_requirements_repository.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/jobs_posted_screen.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

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
  'age': 74,
  'gender': 'female',
  'weight_kg': 58,
  'communication': 'verbal',
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
}) {
  return JobApplicationModel.fromJson({
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
  String? cancelledJobId;

  _FakeIndividualRepository({this.requirements = const [], this.applicationsByJobId = const {}}) : super(Dio());

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
    required String startDate,
    required String careDuration,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    String? frequencyOfCare,
    String? salaryAmount,
  }) async {
    editedJobId = jobId;
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

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
  // Requirement cards accumulate a lot of content (About Patient/Requirement
  // tags, Edit/Cancel/Post Similar actions, applicant review section) — tall
  // enough that the default 800x600 test viewport clips action buttons out
  // of hit-testable range for some fixtures. A generous default surface
  // avoids that for every test in this file, not just the ones that
  // happened to need it first.
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
            ),
        ),
      ],
      child: const MaterialApp(home: JobsPostedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Closed/cancelled/rejected requirements are hidden by default behind a
/// toggle button — tests exercising their card content need to reveal them
/// first.
Future<void> _revealClosedRequirements(WidgetTester tester) async {
  await tester.tap(find.textContaining('Show Closed/Cancelled Requirements'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state with a Post CTA when there are no requirements yet', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    expect(find.textContaining("don't have any requirements posted yet"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('shows the Post CTA again once the only requirement is closed (not live)', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)]),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('shows the Post CTA again once the only requirement was rejected', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, rejectionReason: 'Duplicate posting')],
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('hides the Post CTA while a pending_review requirement is live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)]),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
  });

  testWidgets('hides the Post CTA while an active requirement is live', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
  });

  testWidgets(
      'shows the live requirement up front, and the full history (most recent first) once Show Closed/Cancelled is tapped',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-2', requirementNumber: 43, status: 'active'),
          _requirement(id: 'job-1', requirementNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
      ),
    );

    expect(find.text('Job Id: PAT-JOB-543'), findsOneWidget);
    expect(find.text('Job Id: PAT-JOB-542'), findsNothing);
    expect(find.text('Show Closed/Cancelled Requirements (1)'), findsOneWidget);

    await _revealClosedRequirements(tester);

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
      'a live (active) requirement card has a wide red border on a light green shade — senior-citizen-friendly visibility',
      (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, greaterThanOrEqualTo(2.5));
    expect(border.top.color, AppColors.error);
    expect(decoration.color, AppColors.success.withValues(alpha: 0.06));
  });

  testWidgets('a closed requirement card has a grey border, not red — it is no longer live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      ),
    );
    await _revealClosedRequirements(tester);

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
    await _revealClosedRequirements(tester);

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

  testWidgets('the Salary Guidance Range figure is red, distinct from every other field line\'s dark green',
      (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    final salaryText = tester.widget<Text>(find.text('Salary Guidance Range: ₹1800/day'));
    final span = salaryText.textSpan! as TextSpan;
    final valueSpan = span.children![1] as TextSpan;
    expect(valueSpan.style!.color, AppColors.error);
  });

  testWidgets('the full Patient Details / Care Preferences detail is collapsed by default, and expands on tap',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    // Collapsed by default — not confusing the screen with every field.
    expect(find.text('Patient Details'), findsNothing);
    expect(find.text('74 yrs'), findsNothing);
    expect(find.text('Show Full Details'), findsOneWidget);

    await tester.tap(find.text('Show Full Details'));
    await tester.pumpAndSettle();

    // Same three headings, in the same field order, as the Post/Edit
    // Requirement form — labeled rows, not an undifferentiated chip cloud.
    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('74 yrs'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
    expect(find.text('Nurse Fee Guidance'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('₹1800/day'), findsWidgets);
    expect(find.text('Needs help with daily routine.'), findsOneWidget);
    expect(find.text('Hide Full Details'), findsOneWidget);
  });

  testWidgets(
      'shows Frequency of Care/Salary on the card and in Show Full Details for a pending_review requirement too — '
      'no longer gated behind admin approval', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review')]),
    );

    expect(find.text('Salary Guidance Range: ₹1800/day'), findsOneWidget);

    await tester.tap(find.text('Show Full Details'));
    await tester.pumpAndSettle();

    expect(find.text('Nurse Fee Guidance'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
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
    expect(find.text('Scope Of Work: Click Here'), findsOneWidget);

    await tester.tap(find.text('Scope Of Work: Click Here'));
    await tester.pumpAndSettle();

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
    expect(find.text('Scope Of Work: Click Here'), findsNothing);
  });

  testWidgets('shows Job Id, Salary Guidance Range, and a Duty Requirements link on every card', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    expect(find.text('Job Id: PAT-JOB-542'), findsOneWidget);
    expect(find.text('Salary Guidance Range: ₹1800/day'), findsOneWidget);
    expect(find.text('Duty Requirements: Click Here'), findsOneWidget);

    await tester.tap(find.text('Duty Requirements: Click Here'));
    await tester.pumpAndSettle();

    expect(find.text('24Hrs - Live In'), findsOneWidget);
  });

  testWidgets('shows "No Preference" under Language Preference when languages is empty — '
      'kept in sync with what admin sees, never a blank gap', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(languages: const [], careReceiver: _careReceiverJson)],
      ),
    );

    await tester.tap(find.text('Show Full Details'));
    await tester.pumpAndSettle();

    expect(find.text('Language Preference'), findsOneWidget);
    expect(find.text('No Preference'), findsOneWidget);
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
    expect(find.widgetWithText(TextButton, 'Accept'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'Reject'), findsNWidgets(2));
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

    final expected = DateTime.parse('2026-08-05T10:00:00Z').toLocal();
    expect(
      find.text(
        'Re-applied: ${expected.year}-${expected.month.toString().padLeft(2, '0')}-${expected.day.toString().padLeft(2, '0')} '
        '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}:'
        '${expected.second.toString().padLeft(2, '0')}',
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

    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(icon.color, AppColors.success);
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
      'once a candidate is accepted, every other candidate — including a still-applied one — stays visible '
      'but loses the Accept option; only the accepted one offers Reject (to undo)',
      (tester) async {
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
    expect(find.text('You have accepted a candidate. Reject them to be able to accept someone else.'),
        findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    // The still-applied candidate stays fully visible — just without Accept.
    expect(find.text('Sita Devi'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsNothing);
    // The one Reject button present belongs to the accepted candidate's own
    // tile (undo the acceptance) — Sita, still just 'applied', offers
    // neither Accept nor Reject while someone else is accepted.
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
    // Both candidates' profiles/phones stay reachable regardless.
    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsNWidgets(2));
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

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Decline this candidate'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Changed our mind');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

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
    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsOneWidget);
    // A candidate already decided (rejected) can't be rejected again.
    expect(find.widgetWithText(TextButton, 'Reject'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Accept Anyway'));
    await tester.pumpAndSettle();

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
    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsOneWidget);
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
    await _revealClosedRequirements(tester);

    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsNothing);
  });

  testWidgets('tapping "Accept Anyway" on a completed engagement calls decideApplication with accepted', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [_application(id: 'app-1', status: 'completed')],
      },
    );
    await _pump(tester, repo);
    await _revealClosedRequirements(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Accept Anyway'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
    expect(find.text('Registered Nurse above 2 years of experience'), findsOneWidget);
    expect(find.text('VitaCare-verified caregiver'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets(
      'a closed requirement with a currently-accepted candidate stays visible up front, unlike a plain closed one which stays hidden behind the toggle',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-1', requirementNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
          _requirement(id: 'job-2', requirementNumber: 43, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
        applicationsByJobId: {
          'job-2': [_application(status: 'accepted')],
        },
      ),
    );

    // job-2 (accepted candidate) is up front; job-1 (no accepted candidate)
    // stays behind the toggle.
    expect(find.text('Job Id: PAT-JOB-543'), findsOneWidget);
    expect(find.text('Job Id: PAT-JOB-542'), findsNothing);
    expect(find.text('Show Closed/Cancelled Requirements (1)'), findsOneWidget);

    await _revealClosedRequirements(tester);

    expect(find.text('Job Id: PAT-JOB-542'), findsOneWidget);
  });

  testWidgets('rejecting requires a reason — Confirm stays disabled until something is typed', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Decline this candidate'), findsOneWidget);
    var confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Schedule does not match');
    await tester.pump();
    confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

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

    expect(find.textContaining('Applied:'), findsOneWidget);
    expect(find.textContaining('Accepted by Asha Patel:'), findsOneWidget);

    // Newest first — the most recent action (Accepted) renders above the
    // older one (Applied), not the other way round.
    final acceptedTop = tester.getTopLeft(find.textContaining('Accepted by Asha Patel:')).dy;
    final appliedTop = tester.getTopLeft(find.textContaining('Applied:')).dy;
    expect(acceptedTop, lessThan(appliedTop));
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
    final expected = DateTime.parse('2026-08-05T14:32:00Z').toLocal();
    expect(
      find.text(
        'Rejected by Caregiver: ${expected.year}-${expected.month.toString().padLeft(2, '0')}-${expected.day.toString().padLeft(2, '0')} '
        '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}:'
        '${expected.second.toString().padLeft(2, '0')}',
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
    await _revealClosedRequirements(tester);

    expect(find.text('Closed by Caregiver'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    // Full detail: exactly when the caregiver closed it, not just the label.
    final expected = DateTime.parse('2026-08-06T09:05:00Z').toLocal();
    expect(
      find.text(
        'Closed by Caregiver: ${expected.year}-${expected.month.toString().padLeft(2, '0')}-${expected.day.toString().padLeft(2, '0')} '
        '${expected.hour.toString().padLeft(2, '0')}:${expected.minute.toString().padLeft(2, '0')}:'
        '${expected.second.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the More options menu always offers exactly 3 actions: Edit, Post Similar, Cancel', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // This requirement is itself the account's only live one, so Post
    // Similar is unavailable, while Edit/Cancel stay available (no active
    // application, not yet cancelled/rejected).
    expect(find.text('Edit the Job'), findsOneWidget);
    expect(find.text('Post Similar Requirement (Unavailable)'), findsOneWidget);
    expect(find.text('Cancel the Job'), findsOneWidget);
  });

  testWidgets('Edit the Job is offered (not locked) when there is no active application', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Edit the Job'), findsOneWidget);
    expect(find.text('Edit the Job (Locked)'), findsNothing);
  });

  testWidgets('Edit the Job is disabled (locked) while there is an active (applied) application', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'applied')],
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Edit the Job (Locked)'), findsOneWidget);
    // Disabled — tapping it does nothing, no navigation happens.
    await tester.tap(find.text('Edit the Job (Locked)'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Requirement'), findsNothing);
  });

  testWidgets('rejected/completed applications do not lock editing — Edit the Job stays enabled', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit')],
        },
      ),
    );
    await _revealClosedRequirements(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Edit the Job'), findsOneWidget);
    expect(find.text('Edit the Job (Locked)'), findsNothing);
  });

  testWidgets('tapping Edit the Job opens the edit screen pre-filled with the requirement\'s current values',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit the Job'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Requirement'), findsOneWidget);
    expect(find.text('74'), findsOneWidget); // age, pre-filled
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.controller!.text, 'Indiranagar');
  });

  testWidgets(
      'Cancel the Job is enabled on a live requirement, and confirming it calls cancelRequirement',
      (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Cancel the Job'), findsOneWidget);
    await tester.tap(find.text('Cancel the Job'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this requirement?'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel it'));
    await tester.pumpAndSettle();

    expect(repo.cancelledJobId, 'job-1');
  });

  testWidgets('cancelling the cancel-requirement confirmation dialog does not call cancelRequirement', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel the Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();

    expect(repo.cancelledJobId, isNull);
  });

  testWidgets('shows a Cancelled status and hides the applicants section once cancelled', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.text('Cancelled'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Cancel the Job (Unavailable)'), findsOneWidget);
    // Disabled — tapping it does nothing, no confirmation dialog opens.
    await tester.tap(find.text('Cancel the Job (Unavailable)'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this requirement?'), findsNothing);
    expect(find.textContaining('This requirement was cancelled.'), findsOneWidget);
    expect(find.textContaining('candidate applied in total'), findsNothing);
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
    await _revealClosedRequirements(tester);

    expect(find.text('Rejected'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Cancel the Job (Unavailable)'), findsOneWidget);
  });

  testWidgets(
      'Post Similar Requirement is enabled on a non-live requirement when there is no other live requirement, '
      'and it opens a pre-filled clone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, careReceiver: _careReceiverJson)],
      ),
    );
    await _revealClosedRequirements(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Post Similar Requirement'), findsOneWidget);
    await tester.tap(find.text('Post Similar Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Post Similar Requirement'), findsWidgets);
    expect(find.text('74'), findsOneWidget);
  });

  testWidgets('Post Similar Requirement is disabled while another requirement is still live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-1', requirementNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
          _requirement(id: 'job-2', requirementNumber: 43, status: 'active'),
        ],
      ),
    );
    await _revealClosedRequirements(tester);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Post Similar Requirement (Unavailable)'), findsOneWidget);
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeIndividualRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });
}
