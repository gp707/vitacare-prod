import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_detail_screen.dart';

AdminCaregiverDetail _detail({String status = 'pending_call'}) {
  return AdminCaregiverDetail(
    userId: 'user-1',
    profileId: 'profile-1',
    caregiverNumber: 500,
    fullName: 'Test Caregiver',
    phone: '+919876543210',
    gender: 'female',
    age: 28,
    languages: const ['hindi'],
    preferredCities: const [],
    otherDocumentUrls: const [],
    termsAccepted: false,
    verificationStatus: status,
    hasPendingEdits: false,
    adminNotes: const AdminNotes(),
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminCaregiversRepository extends AdminCaregiversRepository {
  AdminCaregiverDetail detail;
  String? capturedStatus;
  String? capturedRejectionMessage;

  _FakeAdminCaregiversRepository(this.detail) : super(Dio());

  @override
  Future<AdminCaregiverDetail> getDetail(String profileId) async => detail;

  @override
  Future<String> updateStatus(String profileId, String status,
      {String? rejectionMessage}) async {
    capturedStatus = status;
    capturedRejectionMessage = rejectionMessage;
    detail = _detail(status: status);
    return status;
  }
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  _FakeAuditLogsRepository() : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    return const AuditLogListResult(
      items: [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, totalPages: 1),
    );
  }
}

Future<void> _pump(
    WidgetTester tester, _FakeAdminCaregiversRepository repo) async {
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
            ..state = AdminSessionAuthenticated(
                userId: 'admin-1', role: 'super_admin'),
        ),
        adminCaregiversRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider
            .overrideWithValue(_FakeAuditLogsRepository()),
      ],
      child: const MaterialApp(
          home: CaregiverDetailScreen(profileId: 'profile-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Admin Override control regardless of current status',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(status: 'available'));
    await _pump(tester, repo);

    expect(find.text('Admin Override:'), findsOneWidget);
    expect(find.text('Set status to...'), findsOneWidget);
  });

  testWidgets('shows the caregiver display id (NUR-<n>) next to the name',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(status: 'available'));
    await _pump(tester, repo);

    expect(find.text('NUR-500'), findsOneWidget);
  });

  testWidgets(
      'picking a status not reachable via quick-action buttons and setting it calls updateStatus',
      (tester) async {
    // pending_call has no quick-action buttons for e.g. "assigned" — this
    // is exactly the gap the override exists to cover.
    final repo =
        _FakeAdminCaregiversRepository(_detail(status: 'pending_call'));
    await _pump(tester, repo);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assigned').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Set Status'));
    await tester.pumpAndSettle();

    expect(repo.capturedStatus, 'assigned');
    expect(repo.capturedRejectionMessage, isNull);
  });

  testWidgets(
      'selecting Rejected reveals a rejection-message field and passes it through',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(status: 'available'));
    await _pump(tester, repo);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejected').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Rejection message (optional)'),
        findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Rejection message (optional)'),
      'Docs unclear',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Set Status'));
    await tester.pumpAndSettle();

    expect(repo.capturedStatus, 'rejected');
    expect(repo.capturedRejectionMessage, 'Docs unclear');
  });

  testWidgets('Set Status button is disabled until a status is picked',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(status: 'available'));
    await _pump(tester, repo);

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Set Status'));
    expect(button.onPressed, isNull);
  });
}
