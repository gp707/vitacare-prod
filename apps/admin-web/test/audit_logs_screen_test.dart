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
import 'package:admin_web/features/audit_logs/data/audit_log_models.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/audit_logs/screens/audit_logs_screen.dart';
import 'package:admin_web/features/jobs/data/admin_jobs_repository.dart';

AuditLogEntry _entry({
  String id = 'log-1',
  String action = 'status_changed',
  String entityType = 'caregiver_profiles',
  int? jobNumber,
  int? adminJobNumber,
  int? patientJobNumber,
  String? jobId,
  String? targetUserName,
  String? targetUserRole,
  int? targetCaregiverNumber,
  int? targetPatientNumber,
  int? targetOrgNumber,
  int? requirementNumber,
  String? requirementId,
}) {
  return AuditLogEntry.fromJson({
    'id': id,
    'user_id': 'admin-1',
    'user_name': 'Admin One',
    'target_user_id': targetUserName == null ? null : 'target-1',
    'target_user_name': targetUserName,
    'action': action,
    'entity_type': entityType,
    'entity_id': jobId ?? requirementId,
    'job_number': jobNumber,
    'admin_job_number': adminJobNumber,
    'patient_job_number': patientJobNumber,
    'job_id': jobId,
    'target_user_role': targetUserRole,
    'target_caregiver_number': targetCaregiverNumber,
    'target_patient_number': targetPatientNumber,
    'target_org_number': targetOrgNumber,
    'requirement_number': requirementNumber,
    'requirement_id': requirementId,
    'before_value': null,
    'after_value': null,
    'ip_address': null,
    'created_at': '2026-08-17T10:00:00Z',
  });
}

JobModel _jobWithCareReceiver() {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'admin_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'languages': ['hindi'],
    'salary_amount': 30000,
    'preferred_gender': 'female',
    'status': 'active',
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
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    },
  });
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  final List<AuditLogEntry> items;
  _FakeAuditLogsRepository(this.items) : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    return AuditLogListResult(
      items: items,
      meta: const PaginationMeta(page: 1, limit: 20, total: 1, totalPages: 1),
    );
  }
}

class _FakeAdminJobsRepository extends AdminJobsRepository {
  bool getDetailCalled = false;
  String? requestedJobId;

  _FakeAdminJobsRepository() : super(Dio());

  @override
  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async {
    getDetailCalled = true;
    requestedJobId = jobId;
    return (_jobWithCareReceiver(), <JobApplicationModel>[]);
  }
}

Future<void> _pump(WidgetTester tester, _FakeAuditLogsRepository repo, {AdminJobsRepository? jobsRepo}) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        auditLogsRepositoryProvider.overrideWithValue(repo),
        if (jobsRepo != null) adminJobsRepositoryProvider.overrideWithValue(jobsRepo),
      ],
      child: const MaterialApp(home: AuditLogsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows "-" in the Job column for an entry with no resolved job', (tester) async {
    await _pump(tester, _FakeAuditLogsRepository([_entry()]));

    expect(find.text('-'), findsWidgets);
    expect(find.textContaining('ADMIN-JOB-'), findsNothing);
    expect(find.textContaining('PAT-JOB-'), findsNothing);
  });

  testWidgets('shows "ADMIN-JOB-<n>" for a job-related entry, and tapping it opens that job\'s detail dialog',
      (tester) async {
    final jobsRepo = _FakeAdminJobsRepository();
    await _pump(
      tester,
      _FakeAuditLogsRepository([
        _entry(action: 'job_posted', entityType: 'jobs', jobNumber: 42, adminJobNumber: 542, jobId: 'job-1'),
      ]),
      jobsRepo: jobsRepo,
    );

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('job-1'), findsOneWidget,
        reason: 'the exact job id (UUID) must be visible, not just ADMIN-JOB-<n>');

    await tester.tap(find.text('ADMIN-JOB-542'));
    await tester.pumpAndSettle();

    expect(jobsRepo.getDetailCalled, isTrue);
    expect(jobsRepo.requestedJobId, 'job-1');
    expect(find.textContaining('Applicants — ADMIN-JOB-542'), findsOneWidget);
  });

  testWidgets('shows the target caregiver/individual/organisation display id above their name', (tester) async {
    await _pump(
      tester,
      _FakeAuditLogsRepository([
        _entry(
          id: 'log-caregiver',
          targetUserName: 'Ramesh Kumar',
          targetUserRole: 'caregiver',
          targetCaregiverNumber: 542,
        ),
        _entry(
          id: 'log-individual',
          entityType: 'individual_profiles',
          targetUserName: 'Asha Patel',
          targetUserRole: 'individual',
          targetPatientNumber: 501,
        ),
        _entry(
          id: 'log-organisation',
          entityType: 'organisation_profiles',
          targetUserName: 'City Rehab Center',
          targetUserRole: 'organisation',
          targetOrgNumber: 503,
        ),
      ]),
    );

    expect(find.text('NUR-542'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('PAT-501'), findsOneWidget);
    expect(find.text('Asha Patel'), findsOneWidget);
    expect(find.text('ORG-503'), findsOneWidget);
    expect(find.text('City Rehab Center'), findsOneWidget);
  });

  testWidgets('shows just the name (no display id) for an admin/super_admin target', (tester) async {
    await _pump(
      tester,
      _FakeAuditLogsRepository([
        _entry(entityType: 'users', targetUserName: 'Second Admin', targetUserRole: 'admin'),
      ]),
    );

    expect(find.text('Second Admin'), findsOneWidget);
    expect(find.textContaining('NUR-'), findsNothing);
  });

  testWidgets('shows "ORG-JOB-<n>" for an organisation-requirement entry (not clickable, no dialog wired)',
      (tester) async {
    await _pump(
      tester,
      _FakeAuditLogsRepository([
        _entry(
          action: 'org_requirement_posted',
          entityType: 'organisation_requirements',
          requirementNumber: 507,
          requirementId: 'req-1',
        ),
      ]),
    );

    expect(find.text('ORG-JOB-507'), findsOneWidget);
    expect(find.text('req-1'), findsOneWidget,
        reason: 'the exact requirement id (UUID) must be visible, not just ORG-JOB-<n>');
  });
}
