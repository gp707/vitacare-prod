import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/audit_logs/data/audit_log_models.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_detail_screen.dart';

AdminCaregiverDetail _detail() {
  return const AdminCaregiverDetail(
    userId: 'user-1',
    profileId: 'profile-1',
    caregiverNumber: 500,
    fullName: 'Test Caregiver',
    phone: '+919876543210',
    gender: 'female',
    age: 28,
    languages: ['hindi'],
    preferredCities: [],
    otherDocumentUrls: [],
    termsAccepted: false,
    verificationStatus: 'available',
    hasPendingEdits: false,
    adminNotes: AdminNotes(),
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminCaregiversRepository extends AdminCaregiversRepository {
  final AdminCaregiverDetail detail;
  _FakeAdminCaregiversRepository(this.detail) : super(Dio());

  @override
  Future<AdminCaregiverDetail> getDetail(String profileId) async => detail;
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  final List<AuditLogEntry> items;
  _FakeAuditLogsRepository(this.items) : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    return AuditLogListResult(
      items: items,
      meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: 1),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminCaregiversRepository repo, {
  required _FakeAuditLogsRepository auditRepo,
}) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'super_admin'),
        ),
        adminCaregiversRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider.overrideWithValue(auditRepo),
      ],
      child: const MaterialApp(home: CaregiverDetailScreen(profileId: 'profile-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Audit History tab shows the linked job id and the reason for a job decision',
      (tester) async {
    final auditRepo = _FakeAuditLogsRepository([
      AuditLogEntry.fromJson({
        'id': 'log-1',
        'user_id': 'individual-user-1',
        'user_name': 'Asha Patel',
        'target_user_id': 'user-1',
        'target_user_name': 'Test Caregiver',
        'action': 'job_application_decided',
        'entity_type': 'job_applications',
        'entity_id': 'app-1',
        'admin_job_number': null,
        'patient_job_number': 512,
        'job_id': 'job-1',
        'after_value': {'status': 'rejected', 'reason': 'Not a good fit for the schedule'},
        'before_value': null,
        'ip_address': null,
        'created_at': '2026-08-01T10:00:00Z',
      }),
    ]);
    await _pump(tester, _FakeAdminCaregiversRepository(_detail()), auditRepo: auditRepo);

    await tester.tap(find.text('Audit History'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PAT-JOB-512'), findsOneWidget);
    expect(find.text('Reason: Not a good fit for the schedule'), findsOneWidget);
  });
}
