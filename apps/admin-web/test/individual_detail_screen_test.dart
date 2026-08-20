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
import 'package:admin_web/features/individuals/data/admin_individuals_repository.dart';
import 'package:admin_web/features/individuals/screens/individual_detail_screen.dart';

AdminIndividualListItem _item({
  String userId = 'u1',
  int? patientNumber = 500,
  String fullName = 'Asha Patel',
  bool isActive = true,
  bool isJobPostingBlocked = false,
}) {
  return AdminIndividualListItem(
    userId: userId,
    patientNumber: patientNumber,
    fullName: fullName,
    phone: '+919876543210',
    isActive: isActive,
    isJobPostingBlocked: isJobPostingBlocked,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminIndividualsRepository extends AdminIndividualsRepository {
  AdminIndividualListItem detail;
  String? editedUserId;
  Map<String, dynamic>? editedFields;

  _FakeAdminIndividualsRepository(this.detail) : super(Dio());

  @override
  Future<AdminIndividualListItem> getDetail(String userId) async => detail;

  @override
  Future<void> editProfile(String userId, Map<String, dynamic> fields) async {
    editedUserId = userId;
    editedFields = fields;
  }
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  final List<AuditLogEntry> items;
  String? requestedTargetUserId;

  _FakeAuditLogsRepository(this.items) : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    requestedTargetUserId = filters.targetUserId;
    return AuditLogListResult(items: items, meta: const PaginationMeta(page: 1, limit: 50, total: 0, totalPages: 1));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminIndividualsRepository repo, {
  _FakeAuditLogsRepository? auditRepo,
}) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'super_admin'),
        ),
        adminIndividualsRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider.overrideWithValue(auditRepo ?? _FakeAuditLogsRepository([])),
      ],
      child: MaterialApp(home: IndividualDetailScreen(userId: repo.detail.userId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the individual\'s identity, display id, and status', (tester) async {
    await _pump(tester, _FakeAdminIndividualsRepository(_item()));

    expect(find.text('Asha Patel'), findsWidgets);
    expect(find.text('PAT-500'), findsOneWidget);
    expect(find.text('+919876543210'), findsWidgets);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('loads the scoped audit history for this account', (tester) async {
    final auditRepo = _FakeAuditLogsRepository([
      AuditLogEntry.fromJson({
        'id': 'log-1',
        'user_id': 'admin-1',
        'user_name': 'Admin One',
        'target_user_id': 'u1',
        'target_user_name': 'Asha Patel',
        'action': 'admin_edit_profile',
        'entity_type': 'individual_profiles',
        'entity_id': 'u1',
        'before_value': {'full_name': 'Old Name'},
        'after_value': {'full_name': 'Asha Patel'},
        'ip_address': null,
        'created_at': '2026-08-01T10:00:00Z',
      }),
    ]);
    await _pump(tester, _FakeAdminIndividualsRepository(_item()), auditRepo: auditRepo);

    expect(auditRepo.requestedTargetUserId, 'u1');
    expect(find.text('admin_edit_profile'), findsOneWidget);
  });

  testWidgets('tapping Edit reveals a full-name field; saving calls editProfile with only the changed field',
      (tester) async {
    final repo = _FakeAdminIndividualsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Asha Renamed');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editedUserId, 'u1');
    expect(repo.editedFields, {'full_name': 'Asha Renamed'});
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('View full audit log navigates to /audit-logs with this account\'s user id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminIndividualsRepository(_item());

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'super_admin'),
          ),
          adminIndividualsRepositoryProvider.overrideWithValue(repo),
          auditLogsRepositoryProvider.overrideWithValue(_FakeAuditLogsRepository([])),
        ],
        child: MaterialApp(
          home: const IndividualDetailScreen(userId: 'u1'),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Audit Logs Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View full audit log'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/audit-logs');
    expect(pushedArgs, 'u1');
  });
}
