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
  String? jobId,
}) {
  return AuditLogEntry.fromJson({
    'id': id,
    'user_id': 'admin-1',
    'user_name': 'Admin One',
    'target_user_id': null,
    'target_user_name': null,
    'action': action,
    'entity_type': entityType,
    'entity_id': jobId,
    'job_number': jobNumber,
    'job_id': jobId,
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
    expect(find.textContaining('Job #'), findsNothing);
  });

  testWidgets('shows "Job #<n>" for a job-related entry, and tapping it opens that job\'s detail dialog',
      (tester) async {
    final jobsRepo = _FakeAdminJobsRepository();
    await _pump(
      tester,
      _FakeAuditLogsRepository([
        _entry(action: 'job_posted', entityType: 'jobs', jobNumber: 42, jobId: 'job-1'),
      ]),
      jobsRepo: jobsRepo,
    );

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('job-1'), findsOneWidget, reason: 'the exact job id (UUID) must be visible, not just Job #<n>');

    await tester.tap(find.text('Job #42'));
    await tester.pumpAndSettle();

    expect(jobsRepo.getDetailCalled, isTrue);
    expect(jobsRepo.requestedJobId, 'job-1');
    expect(find.textContaining('Applicants — Job #42'), findsOneWidget);
  });
}
