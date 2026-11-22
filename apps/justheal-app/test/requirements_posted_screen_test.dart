import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_state.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/patient_hospital/core/fcm/fcm_service.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/screens/requirements_posted_screen.dart';

/// Equivalent to pumpAndSettle(), but safe once a live (JobStatus.active)
/// requirement's status badge is on screen — its blink animation repeats
/// forever via AnimationController, so a real pumpAndSettle() never
/// observes an idle frame and times out (same reasoning as Individual's own
/// jobs_posted_screen_test.dart _settle helper, mirrored here since
/// _StatusBadge was duplicated onto this screen too). 500ms comfortably
/// clears every real transition in this screen (dialogs/snackbars) without
/// completing even one blink cycle (700ms).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Mirrors _ApplicantTimeline's own toLocal()-then-format logic, so
/// assertions about the rendered date/time stay correct regardless of the
/// test runner's own timezone.
String _localDate(String isoUtc) {
  final d = DateTime.parse(isoUtc).toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _localDateTime(String isoUtc) {
  final d = DateTime.parse(isoUtc).toLocal();
  return '${_localDate(isoUtc)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 5,
  String status = 'active',
  String? rejectionReason,
  String? cancelledAt,
  String typeOfNurse = 'registered_nurse',
  String? typeOfNurseOther,
  int numberOfVacancies = 1,
  String? preferredGender,
  String? experienceRequired = 'fresher',
  String? employmentType = 'full_time',
  String postedAt = '2026-08-01T10:00:00Z',
  int? salaryMin,
  int? salaryMax,
  String? salaryUnit,
}) {
  return OrganisationRequirementModel.fromJson({
    'salary_min': salaryMin,
    'salary_max': salaryMax,
    'salary_unit': salaryUnit,
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': typeOfNurse,
    'type_of_nurse_other': typeOfNurseOther,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Wound care',
    'number_of_vacancies': numberOfVacancies,
    'preferred_gender': preferredGender,
    'experience_required': experienceRequired,
    'employment_type': employmentType,
    'status': status,
    'rejection_reason': rejectionReason,
    'cancelled_at': cancelledAt,
    'posted_at': postedAt,
  });
}

OrganisationRequirementApplicationModel _application({
  String id = 'app-1',
  String requirementId = 'req-1',
  String status = 'applied',
  String appliedAt = '2026-08-01T10:00:00Z',
  String? acceptedAt,
  String? rejectedAt,
  String? completedAt,
  String? reappliedAt,
  String? decidedByName,
  String? declineReason,
  String? decidedBy,
  String updatedAt = '2026-08-01T10:00:00Z',
  String? closeReason,
  int? agreedSalary,
  String? agreedSalaryUnit,
  String? agreedStartDate,
  List<Map<String, dynamic>> agreementHistory = const [],
  double? overallRating,
  String fullName = 'Test Caregiver',
}) {
  return OrganisationRequirementApplicationModel.fromJson({
    'overall_rating': overallRating,
    'agreed_salary': agreedSalary,
    'agreed_salary_unit': agreedSalaryUnit,
    'agreed_start_date': agreedStartDate,
    'agreement_history': agreementHistory,
    'id': id,
    'requirement_id': requirementId,
    'profile_id': 'profile-1',
    'status': status,
    'full_name': fullName,
    'phone': '+919876543210',
    'applied_at': appliedAt,
    'accepted_at': acceptedAt,
    'rejected_at': rejectedAt,
    'completed_at': completedAt,
    'reapplied_at': reappliedAt,
    'decided_by_name': decidedByName,
    'decline_reason': declineReason,
    'decided_by': decidedBy,
    'updated_at': updatedAt,
    'close_reason': closeReason ?? (status == 'completed' ? 'no_reason' : null),
  });
}

class _FakeOrganisationRepository extends OrganisationRepository {
  List<OrganisationRequirementModel> requirements;
  Map<String, List<OrganisationRequirementApplicationModel>> applicationsByRequirementId;
  String? decidedRequirementId;
  String? decidedApplicationId;
  String? decidedStatus;
  String? decidedReason;
  // salary range / agreement calls
  String? salaryRangeRequirementId;
  int? salaryRangeMin;
  int? salaryRangeMax;
  String? salaryRangeUnit;
  ApiException? salaryRangeError;
  String? agreementRequirementId;
  String? agreementApplicationId;
  int? agreementSalary;
  String? agreementUnit;
  String? agreementStartDate;
  String? profileFetchedRequirementId;
  String? profileFetchedApplicationId;
  String? editedRequirementId;
  String? cancelledRequirementId;
  String? reactivatedRequirementId;
  ApiException? reactivateError;

  _FakeOrganisationRepository({this.requirements = const [], this.applicationsByRequirementId = const {}})
      : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> listMyRequirements() async => requirements;

  @override
  Future<List<OrganisationRequirementApplicationModel>> listApplications(String requirementId) async =>
      applicationsByRequirementId[requirementId] ?? const [];

  @override
  Future<void> decideApplication(String requirementId, String applicationId, String status, {String? reason}) async {
    decidedRequirementId = requirementId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
    decidedReason = reason;
  }

  @override
  Future<OrganisationRequirementModel> setSalaryRange(
    String requirementId, {
    required int salaryMin,
    required int salaryMax,
    required String salaryUnit,
  }) async {
    if (salaryRangeError != null) throw salaryRangeError!;
    salaryRangeRequirementId = requirementId;
    salaryRangeMin = salaryMin;
    salaryRangeMax = salaryMax;
    salaryRangeUnit = salaryUnit;
    return _requirement(id: requirementId);
  }

  @override
  Future<void> setAgreement(
    String requirementId,
    String applicationId, {
    required int salary,
    required String salaryUnit,
    required String startDate,
  }) async {
    agreementRequirementId = requirementId;
    agreementApplicationId = applicationId;
    agreementSalary = salary;
    agreementUnit = salaryUnit;
    agreementStartDate = startDate;
  }

  @override
  Future<OrganisationRequirementModel> editRequirement(
    String requirementId, {
    required String typeOfNurse,
    String? typeOfNurseOther,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
    required int numberOfVacancies,
    String? preferredGender,
    String? experienceRequired,
    String? employmentType,
  }) async {
    editedRequirementId = requirementId;
    return _requirement(id: requirementId);
  }

  @override
  Future<void> cancelRequirement(String requirementId) async {
    cancelledRequirementId = requirementId;
  }

  @override
  Future<OrganisationRequirementModel> reactivateRequirement(String requirementId) async {
    if (reactivateError != null) throw reactivateError!;
    reactivatedRequirementId = requirementId;
    return _requirement(id: requirementId, status: 'active');
  }

  @override
  Future<CaregiverProfileModel> getApplicantProfile(String requirementId, String applicationId) async {
    profileFetchedRequirementId = requirementId;
    profileFetchedApplicationId = applicationId;
    return CaregiverProfileModel.fromJson({
      'user_id': 'user-1',
      'profile_id': 'profile-1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'female',
      'age': 30,
      'languages': ['hindi'],
      'highest_qualification': 'gda_non_nursing',
      'religion': 'hindu',
      'terms_accepted': true,
      'verification_status': 'available',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

/// Each applicant's activity log is collapsed by default — tap every
/// "Show Activity Log" link so the timeline entries become visible.
Future<void> _expandAllActivityLogs(WidgetTester tester) async {
  var guard = 0;
  while (find.text('Show Activity Log').evaluate().isNotEmpty && guard++ < 20) {
    // The card is taller than the test screen: scroll the link into view before tapping it.
    await tester.ensureVisible(find.text('Show Activity Log').first);
    await tester.tap(find.text('Show Activity Log').first);
    await _settle(tester);
  }
}

Future<void> _pump(WidgetTester tester, _FakeOrganisationRepository repo, {bool isJobPostingBlocked = false}) async {
  // A tall screen, so every card (they have grown) is fully on screen and every tap lands.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        organisationRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, IndividualRepository(Dio()), repo, FcmService(IndividualRepository(Dio()), OrganisationRepository(Dio())))
            ..state = SessionAuthenticated(
              role: 'organisation',
              fullName: 'Ravi Sharma',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
              organisationName: 'City Hospital',
              organisationType: 'hospital',
              city: 'bangalore',
              area: 'Indiranagar',
            ),
        ),
      ],
      child: const MaterialApp(home: RequirementsPostedScreen()),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('shows an empty state and the Post CTA when there are no requirements yet', (tester) async {
    await _pump(tester, _FakeOrganisationRepository());

    expect(find.textContaining("don't have any requirements posted yet"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('the Post CTA stays visible even with multiple live requirements — no one-live limit like Individual',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [
          _requirement(id: 'req-1', requirementNumber: 1, status: 'active'),
          _requirement(id: 'req-2', requirementNumber: 2, status: 'pending_review'),
        ],
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNotNull);
    expect(find.text('ORG-JOB-1'), findsOneWidget);
    expect(find.text('ORG-JOB-2'), findsOneWidget);
  });

  testWidgets(
      'shows the most recently posted requirement first, whatever its status', (tester) async {
    // 4 full requirement cards need more vertical room than the default
    // test surface to all lay out within the ListView's cache extent.
    await tester.binding.setSurfaceSize(const Size(400, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [
          _requirement(
            id: 'req-new-pending',
            requirementNumber: 3,
            status: 'pending_review',
            postedAt: '2026-08-03T10:00:00Z',
          ),
          _requirement(
            id: 'req-old-active',
            requirementNumber: 1,
            status: 'active',
            postedAt: '2026-08-01T10:00:00Z',
          ),
          _requirement(
            id: 'req-newer-active',
            requirementNumber: 2,
            status: 'active',
            postedAt: '2026-08-02T10:00:00Z',
          ),
          _requirement(
            id: 'req-closed',
            requirementNumber: 4,
            status: 'closed',
            postedAt: '2026-08-04T10:00:00Z',
          ),
        ],
      ),
    );

    double top(String id) => tester.getTopLeft(find.text(id)).dy;

    // Posted 08-04, 08-03, 08-02, 08-01 — strictly newest first.
    expect(top('ORG-JOB-4'), lessThan(top('ORG-JOB-3')));
    expect(top('ORG-JOB-3'), lessThan(top('ORG-JOB-2')));
    expect(top('ORG-JOB-2'), lessThan(top('ORG-JOB-1')));
  });

  testWidgets('shows requirement details: type of nurse, experience/employment, accommodation/food, and a '
      'View Full Details link (Special Skills moved to its own page)', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(experienceRequired: '5_10_years', employmentType: 'part_time')],
      ),
    );

    expect(find.text('Live — visible to caregivers'), findsOneWidget);
    expect(find.text('Registered Nurse'), findsOneWidget);
    expect(find.text('5-10 Years'), findsOneWidget);
    expect(find.text('Part Time'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Wound care'), findsNothing);
    expect(find.text('View Full Details'), findsOneWidget);
  });

  testWidgets('tapping View Full Details opens a page with the full Special Skills text', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(requirements: [_requirement()]),
    );

    await tester.tap(find.text('View Full Details'));
    await tester.pumpAndSettle();

    expect(find.text('Wound care'), findsOneWidget);
  });

  testWidgets('shows "Preferred: No Preference" on the card when preferredGender is not set', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(requirements: [_requirement(preferredGender: null)]),
    );

    expect(find.text('Preferred: No Preference'), findsOneWidget);
  });

  testWidgets('highlights the status as a rounded, color-coded pill instead of plain text', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(requirements: [_requirement(status: 'active')]),
    );

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Live — visible to caregivers'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(999));
    expect(decoration.border, isNotNull);
    expect(decoration.color, AppColors.success.withValues(alpha: 0.12));
  });

  testWidgets('shows the accepted caregiver on a closed requirement', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByRequirementId: {
          'req-1': [_application(status: 'accepted')],
        },
      ),
    );

    expect(find.text('Closed — caregiver assigned'), findsOneWidget);
    expect(find.byKey(const Key('applicant-name-app-1')), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets(
      'shows the full per-candidate log — actor, action, date/time, and reason — not just the bare status',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByRequirementId: {
          'req-1': [
            _application(
              status: 'rejected',
              appliedAt: '2026-08-01T10:00:00Z',
              rejectedAt: '2026-08-02T11:30:15Z',
              decidedByName: 'Ravi Sharma',
              declineReason: 'Not enough experience',
            ),
          ],
        },
      ),
    );

    // Computed via toLocal() same as the widget under test, since the
    // runner's own timezone can shift the displayed date/hour away from
    // the UTC literals above.
    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Applied: ${_localDate('2026-08-01T10:00:00Z')}'), findsOneWidget);
    expect(
      find.textContaining('Rejected by Ravi Sharma: ${_localDateTime('2026-08-02T11:30:15Z')}'),
      findsOneWidget,
    );
    expect(find.textContaining('Reason: Not enough experience'), findsOneWidget);
  });

  testWidgets(
      'shows a Re-applied line — and clears the prior rejection — once a caregiver re-applies after being '
      'rejected (mirrors Individual\'s own timeline and caregiver-app\'s)', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {
          'req-1': [
            _application(
              status: 'applied',
              appliedAt: '2026-08-05T09:00:00Z',
              reappliedAt: '2026-08-05T09:00:00Z',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Re-applied: ${_localDateTime('2026-08-05T09:00:00Z')}'), findsOneWidget);
    expect(find.textContaining('Rejected'), findsNothing);
  });

  testWidgets('shows "Rejected by Caregiver" (no reason) when the caregiver withdrew their own application',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {
          'req-1': [
            _application(status: 'rejected', rejectedAt: '2026-08-02T11:30:15Z', decidedByName: null),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(
      find.textContaining('Rejected by Caregiver: ${_localDate('2026-08-02T11:30:15Z')}'),
      findsOneWidget,
    );
    expect(find.textContaining('Reason:'), findsNothing);
  });

  testWidgets('shows "Accepted by <name>" and "Closed by Caregiver" for an accepted-then-completed candidate',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'active')],
        applicationsByRequirementId: {
          'req-1': [
            _application(
              status: 'completed',
              acceptedAt: '2026-08-02T09:00:00Z',
              completedAt: '2026-08-05T18:00:00Z',
              decidedByName: 'Ravi Sharma',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(
      find.textContaining('Accepted by Ravi Sharma: ${_localDate('2026-08-02T09:00:00Z')}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Closed by Caregiver: ${_localDate('2026-08-05T18:00:00Z')}'),
      findsOneWidget,
    );
    // Defaults to "No Reason" when the fixture doesn't specify one.
    expect(find.textContaining('Reason: No Reason'), findsOneWidget);
  });

  testWidgets(
      'still shows the earlier Rejected entry (with reason) after accepting anyway — history is no longer '
      'lost the moment status flips to accepted', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'active')],
        applicationsByRequirementId: {
          'req-1': [
            _application(
              status: 'accepted',
              appliedAt: '2026-08-01T09:00:00Z',
              rejectedAt: '2026-08-02T09:00:00Z',
              declineReason: 'Not a fit',
              decidedByName: 'Ravi Sharma',
              acceptedAt: '2026-08-03T09:00:00Z',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Applied:'), findsOneWidget);
    expect(find.textContaining('Rejected by Ravi Sharma:'), findsOneWidget);
    expect(find.textContaining('Reason: Not a fit'), findsOneWidget);
    expect(find.textContaining('Accepted by Ravi Sharma:'), findsOneWidget);
  });

  testWidgets('shows a specific close reason in the timeline when the caregiver picked one', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'active')],
        applicationsByRequirementId: {
          'req-1': [
            _application(
              status: 'completed',
              acceptedAt: '2026-08-02T09:00:00Z',
              completedAt: '2026-08-05T18:00:00Z',
              closeReason: 'temporarily_not_available',
            ),
          ],
        },
      ),
    );

    await _expandAllActivityLogs(tester);
    expect(find.textContaining('Reason: Temporarily Not Available'), findsOneWidget);
  });

  testWidgets('accepting an applicant calls decideApplication with the right requirement and application id',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await _settle(tester);

    expect(repo.decidedRequirementId, 'req-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
    // the agreed-salary popup follows; skip it here
    await tester.tap(find.text('Fill later'));
    await _settle(tester);
  });

  testWidgets('rejecting an applicant requires a reason — Confirm stays disabled until something is typed',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await _settle(tester);

    final confirmButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Not enough experience');
    await _settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await _settle(tester);

    expect(repo.decidedRequirementId, 'req-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Not enough experience');
  });

  testWidgets('a previously-rejected applicant can be re-accepted via "Accept Anyway"', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed')],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'rejected')],
      },
    );
    await _pump(tester, repo);

    expect(find.widgetWithText(FilledButton, 'Accept Anyway'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept Anyway'));
    await _settle(tester);

    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
    await tester.tap(find.text('Fill later'));
    await _settle(tester);
  });

  testWidgets(
      'while one applicant is already accepted, another undecided candidate still offers Accept — '
      'number_of_vacancies is informational only, never an accept cap', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed', numberOfVacancies: 1)],
        applicationsByRequirementId: {
          'req-1': [
            _application(id: 'app-1', status: 'accepted'),
            _application(id: 'app-2', status: 'applied'),
          ],
        },
      ),
    );

    // The already-accepted applicant offers Reject (undo), not Accept.
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reject'), findsNWidgets(2));
  });

  testWidgets('tapping View Profile on an undecided applicant opens their full profile', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedRequirementId, 'req-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('View Profile is also available for an already-decided (accepted) applicant', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed')],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'accepted')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeOrganisationRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });

  testWidgets('shows Number of Vacancies, Preferred Gender, and Type of Nurse "Others" free text on the card',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(
          typeOfNurse: 'others',
          typeOfNurseOther: 'Physiotherapist',
          numberOfVacancies: 7,
          preferredGender: 'female',
        ),
      ],
    );
    await _pump(tester, repo);

    expect(find.textContaining('Physiotherapist'), findsOneWidget);
    expect(find.text('Vacancies: 7'), findsOneWidget);
    expect(find.text('Preferred: Female'), findsOneWidget);
  });

  testWidgets(
      'the More options menu always offers exactly 4 actions, Hide/Unhide listed first: Hide, Unhide, Edit, '
      'Post Similar', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Hide Job for New Applications'), findsOneWidget);
    expect(find.text('Unhide and Make it Live (Unavailable)'), findsOneWidget);
    expect(find.text('Edit the Requirement'), findsOneWidget);
    expect(find.text('Post Similar Requirement'), findsOneWidget);

    // Hide/Unhide are listed first, above Edit/Post Similar.
    final hideY = tester.getTopLeft(find.text('Hide Job for New Applications')).dy;
    final unhideY = tester.getTopLeft(find.text('Unhide and Make it Live (Unavailable)')).dy;
    final editY = tester.getTopLeft(find.text('Edit the Requirement')).dy;
    final postSimilarY = tester.getTopLeft(find.text('Post Similar Requirement')).dy;
    expect(hideY, lessThan(unhideY));
    expect(unhideY, lessThan(editY));
    expect(editY, lessThan(postSimilarY));
  });

  testWidgets('Edit the Requirement is disabled (locked) while there is an active (applied) application',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'applied')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Edit the Requirement (Locked)'), findsOneWidget);
  });

  testWidgets('a completed (closed duty) or accepted application keeps editing locked', (tester) async {
    for (final status in ['accepted', 'completed']) {
      final repo = _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {
          'req-1': [_application(status: status)],
        },
      );
      await _pump(tester, repo);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);

      expect(find.text('Edit the Requirement (Locked)'), findsOneWidget);
      expect(find.text('Edit the Requirement'), findsNothing);

      // Dismiss the popup menu before the next iteration re-pumps — the
      // widget tree shape is identical across iterations (same
      // ProviderScope/MaterialApp/RequirementsPostedScreen structure, only
      // the repo's data differs), so Flutter's element reconciliation can
      // otherwise carry the still-open PopupMenuButton route over into the
      // next iteration's fresh pump, intercepting its more_vert tap.
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
    }
  });

  testWidgets('editing unlocks when every candidate was rejected, and stays locked if one is still waiting',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {
          'req-1': [_application(id: 'a', status: 'rejected'), _application(id: 'b', status: 'rejected')],
        },
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Edit the Requirement'), findsOneWidget);
    expect(find.text('Edit the Requirement (Locked)'), findsNothing);
  });

  testWidgets('Hide Job for New Applications is disabled once the requirement was admin-rejected', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(status: 'closed', rejectionReason: 'Not needed'),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Hide Job for New Applications (Unavailable)'), findsOneWidget);
  });

  testWidgets('Hide Job for New Applications is disabled once already hidden, and shows a Hidden status',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z'),
      ],
    );
    await _pump(tester, repo);

    expect(find.text('Hidden'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Hide Job for New Applications (Unavailable)'), findsOneWidget);
    // Unhide is the mirror image — disabled everywhere except once
    // actually hidden.
    expect(find.text('Unhide and Make it Live'), findsOneWidget);
  });

  testWidgets('Unhide and Make it Live is disabled (Unavailable) for a live requirement', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Unhide and Make it Live (Unavailable)'), findsOneWidget);
  });

  testWidgets('tapping Unhide and Make it Live calls reactivateRequirement and reloads, no confirmation needed',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z')],
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Unhide and Make it Live'));
    await _settle(tester);

    expect(repo.reactivatedRequirementId, 'req-1');
  });

  testWidgets('shows the server error message if reactivating fails (e.g. JOB_010, job posting blocked)',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z')],
    )..reactivateError = const ApiException(
        code: 'JOB_010', message: 'Your account is blocked from posting new requirements');
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Unhide and Make it Live'));
    await _settle(tester);

    expect(find.text('Your account is blocked from posting new requirements'), findsOneWidget);

    // Drain the still-pending 5s auto-dismiss timer so the test doesn't
    // end with a live Timer outliving the widget tree.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('confirming Hide Job for New Applications calls cancelRequirement and reloads', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Hide Job for New Applications'));
    await _settle(tester);

    expect(find.text('Hide this job for new applications?'), findsOneWidget);
    expect(
      find.textContaining('You can unhide and make it live again anytime'),
      findsOneWidget,
    );
    await tester.tap(find.text('Yes, hide it'));
    await _settle(tester);

    expect(repo.cancelledRequirementId, 'req-1');
  });

  testWidgets('cancelling the hide-job confirmation dialog does not call cancelRequirement',
      (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Hide Job for New Applications'));
    await _settle(tester);
    await tester.tap(find.text('No, keep it live'));
    await _settle(tester);

    expect(repo.cancelledRequirementId, isNull);
  });

  testWidgets('tapping Edit the Requirement opens the edit screen pre-filled with current values', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement(typeOfNurse: 'auxiliary_nurse')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Edit the Requirement'));
    await _settle(tester);

    expect(find.text('Edit Requirement'), findsOneWidget);
    expect(find.text('Auxiliary Nurse'), findsOneWidget);
  });

  testWidgets('Post Similar Requirement is always enabled — no one-live limit like Individual', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Post Similar Requirement'));
    await _settle(tester);

    expect(find.text('Post a Requirement'), findsOneWidget);
  });

  group('salary range on a requirement', () {
    testWidgets('shows the range on the card, per month or per day', (tester) async {
      await _pump(tester, _FakeOrganisationRepository(requirements: [
        _requirement(id: 'req-1', salaryMin: 20000, salaryMax: 30000, salaryUnit: 'monthly'),
      ]));
      expect(find.text('₹20,000 – ₹30,000 per month'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
    });

    testWidgets('says "not set" with an Add button when no range was given', (tester) async {
      await _pump(tester, _FakeOrganisationRepository(requirements: [_requirement()]));
      expect(find.text('Salary range not set'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
    });

    testWidgets('can be edited after posting and saves min, max and unit', (tester) async {
      final repo = _FakeOrganisationRepository(requirements: [
        _requirement(salaryMin: 20000, salaryMax: 30000, salaryUnit: 'monthly'),
      ]);
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('edit-salary-range')));
      await _settle(tester);
      // pre-filled with what is saved
      expect(tester.widget<TextField>(find.byKey(const Key('salary-range-min'))).controller!.text, '20000');
      await tester.enterText(find.byKey(const Key('salary-range-min')), '900');
      await tester.enterText(find.byKey(const Key('salary-range-max')), '1200');
      await tester.tap(find.text('Per day'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(repo.salaryRangeRequirementId, 'req-1');
      expect(repo.salaryRangeMin, 900);
      expect(repo.salaryRangeMax, 1200);
      expect(repo.salaryRangeUnit, 'daily');
    });

    testWidgets('can be edited even though the rest of the requirement is locked by an applicant', (tester) async {
      final repo = _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {'req-1': [_application()]},
      );
      await _pump(tester, repo);
      // the requirement itself is locked...
      await tester.tap(find.byTooltip('More options'));
      await _settle(tester);
      expect(find.text('Edit the Requirement (Locked)'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);
      // ...but the salary range is not
      await tester.tap(find.byKey(const Key('edit-salary-range')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('salary-range-min')), '15000');
      await tester.enterText(find.byKey(const Key('salary-range-max')), '18000');
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(repo.salaryRangeMin, 15000);
    });

    testWidgets('refuses an empty, half-filled or inverted range without calling the server', (tester) async {
      final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('edit-salary-range')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(find.byKey(const Key('salary-range-error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('salary-range-min')), '900');
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(find.text('Enter both the lowest and the highest salary'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('salary-range-max')), '500');
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(find.text('The highest salary cannot be below the lowest'), findsOneWidget);
      expect(repo.salaryRangeMin, isNull);
    });

    testWidgets('a server error is shown in the sheet, which stays open', (tester) async {
      final repo = _FakeOrganisationRepository(requirements: [_requirement()])
        ..salaryRangeError = ApiException(code: 'GEN_001', message: 'Invalid salary range');
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('edit-salary-range')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('salary-range-min')), '900');
      await tester.enterText(find.byKey(const Key('salary-range-max')), '1200');
      await tester.tap(find.byKey(const Key('salary-range-save')));
      await _settle(tester);
      expect(find.text('Invalid salary range'), findsOneWidget);
      expect(find.byKey(const Key('salary-range-save')), findsOneWidget);
    });
  });

  group('final salary and start date after hiring', () {
    _FakeOrganisationRepository repoWith(List<OrganisationRequirementApplicationModel> apps) => _FakeOrganisationRepository(
          requirements: [_requirement(salaryMin: 20000, salaryMax: 30000, salaryUnit: 'monthly')],
          applicationsByRequirementId: {'req-1': apps},
        );

    testWidgets('accepting a caregiver opens the "Confirm salary and start date" popup right away', (tester) async {
      final repo = repoWith([_application()]);
      await _pump(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await _settle(tester);
      expect(find.text('Confirm salary and start date'), findsOneWidget);
      // the organisation version has no paragraph addressed to a family
      expect(find.textContaining('house maids'), findsNothing);
      // "per month" is preselected from the posting's own range unit
      expect(find.textContaining('Agreed Salary (₹ per month)'), findsOneWidget);
      await tester.tap(find.text('Fill later'));
      await _settle(tester);
      expect(repo.agreementSalary, isNull);
    });

    testWidgets('saving the popup sends the salary, its unit and the start date for that caregiver', (tester) async {
      final repo = repoWith([_application()]);
      await _pump(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, '26000');
      await tester.tap(find.text('Select a date'));
      await _settle(tester);
      await tester.tap(find.text('OK'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save & send to caregiver'));
      await _settle(tester);
      expect(repo.agreementRequirementId, 'req-1');
      expect(repo.agreementApplicationId, 'app-1');
      expect(repo.agreementSalary, 26000);
      expect(repo.agreementUnit, 'monthly');
      expect(repo.agreementStartDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    testWidgets('an accepted caregiver with nothing entered shows a button to enter salary and start date', (tester) async {
      await _pump(tester, repoWith([_application(status: 'accepted', acceptedAt: '2026-08-02T10:00:00Z')]));
      expect(find.text('Salary and start date not entered yet'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Enter salary and start date'), findsOneWidget);
    });

    testWidgets('once entered, the agreed salary and start date are on ONE line, with an Edit button', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(status: 'accepted', acceptedAt: '2026-08-02T10:00:00Z', agreedSalary: 25000, agreedSalaryUnit: 'monthly', agreedStartDate: '2026-12-01'),
        ]),
      );
      final line = find.byKey(const Key('agreement-line-app-1'));
      expect(line, findsOneWidget);
      final text = tester.widget<Text>(line).data!;
      expect(text, contains('Agreed salary: ₹25,000 per month'));
      expect(text, contains('Starts 1 Dec 2026'));
      expect(text, isNot(contains('\n')));
      expect(find.widgetWithText(OutlinedButton, 'Edit salary and start date'), findsOneWidget);
    });

    testWidgets('editing opens the popup filled with the saved values and saves the change', (tester) async {
      final repo = repoWith([
        _application(status: 'accepted', acceptedAt: '2026-08-02T10:00:00Z', agreedSalary: 25000, agreedSalaryUnit: 'monthly', agreedStartDate: '2099-12-01'),
      ]);
      await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('agreement-button-app-1')));
      await _settle(tester);
      expect(find.text('25000'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '27000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save & send to caregiver'));
      await _settle(tester);
      expect(repo.agreementSalary, 27000);
      expect(repo.agreementStartDate, '2099-12-01');
    });

    testWidgets('a rejected, waiting or closed caregiver has no way to enter or change salary and start date', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(id: 'r', status: 'rejected', rejectedAt: '2026-08-02T10:00:00Z', agreedSalary: 25000, agreedSalaryUnit: 'monthly', agreedStartDate: '2026-12-01'),
          _application(id: 'w', status: 'applied'),
          _application(id: 'c', status: 'completed', completedAt: '2026-08-03T10:00:00Z'),
        ]),
      );
      expect(find.byKey(const Key('agreement-button-r')), findsNothing);
      expect(find.byKey(const Key('agreement-button-w')), findsNothing);
      expect(find.byKey(const Key('agreement-button-c')), findsNothing);
      expect(find.textContaining('Agreed salary'), findsNothing);
    });

    testWidgets('the activity log lists every entry and change of salary and start date, with thin separators', (tester) async {
      await _pump(
        tester,
        repoWith([
          _application(
            status: 'accepted',
            acceptedAt: '2026-08-02T10:00:00Z',
            agreedSalary: 25000,
            agreedSalaryUnit: 'monthly',
            agreedStartDate: '2026-12-01',
            agreementHistory: [
              {'salary': 20000, 'unit': 'monthly', 'start_date': '2026-11-25', 'at': '2026-08-03T10:00:00Z'},
              {'salary': 25000, 'unit': 'monthly', 'start_date': '2026-12-01', 'at': '2026-08-04T10:00:00Z'},
            ],
          ),
        ]),
      );
      await _expandAllActivityLogs(tester);
      expect(find.textContaining('Salary and start date entered'), findsOneWidget);
      expect(find.textContaining('Salary and start date changed'), findsOneWidget);
      expect(find.textContaining('₹20,000 per month, starts 25 Nov 2026'), findsOneWidget);
      expect(find.textContaining('₹25,000 per month, starts 1 Dec 2026'), findsOneWidget);
      // applied + accepted + entered + changed = 4 entries -> 3 separators
      expect(find.byKey(const Key('org-log-separator-1')), findsOneWidget);
      expect(find.byKey(const Key('org-log-separator-3')), findsOneWidget);
      expect(find.byKey(const Key('org-log-separator-4')), findsNothing);
    });
  });

  group('applicant tile header', () {
    testWidgets('no picture or star arc on the tile; name is a tappable link, phone below', (tester) async {
      await _pump(
        tester,
        _FakeOrganisationRepository(
          requirements: [_requirement()],
          applicationsByRequirementId: {
            'req-1': [_application(id: 'rated', fullName: 'Asha Rated', overallRating: 3.5)],
          },
        ),
      );
      expect(find.byKey(const Key('rating-arc-avatar')), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byKey(const Key('applicant-name-rated')), findsOneWidget);
      expect(find.byKey(const Key('call-button')), findsOneWidget);
    });
  });
}
