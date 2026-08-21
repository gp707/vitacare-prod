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
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';
import 'package:admin_web/features/organisations/screens/organisation_detail_screen.dart';

AdminOrganisationListItem _item({
  String userId = 'u1',
  int? orgNumber = 500,
  String fullName = 'Dr. Rao',
  String organisationName = 'City Rehab Center',
  String organisationType = OrganisationType.hospital,
  bool isActive = true,
  bool isJobPostingBlocked = false,
}) {
  return AdminOrganisationListItem(
    userId: userId,
    orgNumber: orgNumber,
    fullName: fullName,
    phone: '+919876543210',
    organisationName: organisationName,
    organisationType: organisationType,
    city: City.bangalore,
    area: 'Whitefield',
    isActive: isActive,
    isJobPostingBlocked: isJobPostingBlocked,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminOrganisationsRepository extends AdminOrganisationsRepository {
  AdminOrganisationListItem detail;
  String? editedUserId;
  Map<String, dynamic>? editedFields;

  _FakeAdminOrganisationsRepository(this.detail) : super(Dio());

  @override
  Future<AdminOrganisationListItem> getDetail(String userId) async => detail;

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
    return AuditLogListResult(
        items: items,
        meta:
            const PaginationMeta(page: 1, limit: 50, total: 0, totalPages: 1));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminOrganisationsRepository repo, {
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
            ..state = AdminSessionAuthenticated(
                userId: 'admin-1', role: 'super_admin'),
        ),
        adminOrganisationsRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider
            .overrideWithValue(auditRepo ?? _FakeAuditLogsRepository([])),
      ],
      child: MaterialApp(
          home: OrganisationDetailScreen(userId: repo.detail.userId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'shows the organisation\'s identity, display id, type, location, and status',
      (tester) async {
    await _pump(tester, _FakeAdminOrganisationsRepository(_item()));

    expect(find.text('City Rehab Center'), findsWidgets);
    expect(find.text('ORG-500'), findsOneWidget);
    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('Hospital'), findsOneWidget);
    expect(find.text('Bangalore'), findsOneWidget);
    expect(find.text('Whitefield'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('loads the scoped audit history for this account',
      (tester) async {
    final auditRepo = _FakeAuditLogsRepository([
      AuditLogEntry.fromJson({
        'id': 'log-1',
        'user_id': 'admin-1',
        'user_name': 'Admin One',
        'target_user_id': 'u1',
        'target_user_name': 'City Rehab Center',
        'action': 'admin_edit_profile',
        'entity_type': 'organisation_profiles',
        'entity_id': 'u1',
        'before_value': {'organisation_name': 'Old Name'},
        'after_value': {'organisation_name': 'City Rehab Center'},
        'ip_address': null,
        'created_at': '2026-08-01T10:00:00Z',
      }),
    ]);
    await _pump(tester, _FakeAdminOrganisationsRepository(_item()),
        auditRepo: auditRepo);

    expect(auditRepo.requestedTargetUserId, 'u1');
    expect(find.text('admin_edit_profile'), findsOneWidget);
  });

  testWidgets(
      'tapping Edit reveals editable fields; saving calls editProfile with only the changed fields',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Organisation Name'),
        'Renamed Rehab Center');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editedUserId, 'u1');
    expect(repo.editedFields, {'organisation_name': 'Renamed Rehab Center'});
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets(
      'View full audit log navigates to /audit-logs with this account\'s user id',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminOrganisationsRepository(_item());

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(
                  userId: 'admin-1', role: 'super_admin'),
          ),
          adminOrganisationsRepositoryProvider.overrideWithValue(repo),
          auditLogsRepositoryProvider
              .overrideWithValue(_FakeAuditLogsRepository([])),
        ],
        child: MaterialApp(
          home: const OrganisationDetailScreen(userId: 'u1'),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Text('Audit Logs Screen')));
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
