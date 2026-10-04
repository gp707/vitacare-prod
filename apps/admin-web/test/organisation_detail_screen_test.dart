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
  String? blockedUserId;
  String? blockedLevel;
  String? blockedReason;
  String? unblockedUserId;
  String? unblockedLevel;
  String? resetCodeUserId;
  String? resetCodeValue;
  String? notesUserId;
  String? notesValue;

  _FakeAdminOrganisationsRepository(this.detail) : super(Dio());

  @override
  Future<void> resetCode(String userId, String code) async {
    resetCodeUserId = userId;
    resetCodeValue = code;
  }

  @override
  Future<void> upsertNotes(String userId, String? notes) async {
    notesUserId = userId;
    notesValue = notes;
    detail = _item(
        userId: detail.userId,
        fullName: detail.fullName,
        organisationName: detail.organisationName);
  }

  @override
  Future<AdminOrganisationListItem> getDetail(String userId) async => detail;

  @override
  Future<void> editProfile(String userId, Map<String, dynamic> fields) async {
    editedUserId = userId;
    editedFields = fields;
  }

  @override
  Future<void> block(String userId, String level, String reason) async {
    blockedUserId = userId;
    blockedLevel = level;
    blockedReason = reason;
    detail = level == 'full'
        ? _item(
            userId: detail.userId,
            fullName: detail.fullName,
            organisationName: detail.organisationName,
            isActive: false)
        : _item(
            userId: detail.userId,
            fullName: detail.fullName,
            organisationName: detail.organisationName,
            isJobPostingBlocked: true);
  }

  @override
  Future<void> unblock(String userId, String level) async {
    unblockedUserId = userId;
    unblockedLevel = level;
    detail = _item(
        userId: detail.userId,
        fullName: detail.fullName,
        organisationName: detail.organisationName);
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
      'shows the linked requirement id and the close reason for a caregiver-closed entry',
      (tester) async {
    final auditRepo = _FakeAuditLogsRepository([
      AuditLogEntry.fromJson({
        'id': 'log-2',
        'user_id': 'caregiver-user-1',
        'user_name': 'Ramesh Kumar',
        'target_user_id': 'u1',
        'target_user_name': 'City Rehab Center',
        'action': 'org_requirement_application_decided',
        'entity_type': 'organisation_requirement_applications',
        'entity_id': 'app-1',
        'requirement_number': 700,
        'requirement_id': 'req-1',
        'after_value': {'status': 'completed', 'close_reason': 'need_to_go_hometown'},
        'ip_address': null,
        'created_at': '2026-08-01T10:00:00Z',
      }),
    ]);
    await _pump(tester, _FakeAdminOrganisationsRepository(_item()),
        auditRepo: auditRepo);

    expect(find.textContaining('ORG-JOB-700'), findsOneWidget);
    expect(find.text('Reason: need_to_go_hometown'), findsOneWidget);
  });

  testWidgets(
      'tapping Edit reveals editable fields; saving calls editProfile with only the changed fields',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    // Two Edit buttons exist now (Profile section + Notes section below it)
    // — the Profile one comes first in the widget tree.
    await tester.tap(find.text('Edit').first);
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
      'editing the Phone field and saving calls editProfile with only the changed phone field',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '+919999999999');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.editedUserId, 'u1');
    expect(repo.editedFields, {'phone': '+919999999999'});
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

  testWidgets('shows Block Posting and Block Profile for an active, unblocked account', (tester) async {
    await _pump(tester, _FakeAdminOrganisationsRepository(_item()));

    expect(find.widgetWithText(OutlinedButton, 'Block Posting'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Block Profile'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Unblock Posting'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Unblock'), findsNothing);
  });

  testWidgets('tapping Block Posting asks for a reason and calls block with level job_posting', (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Block Posting'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reason (shown to the organisation)'), 'Spam postings');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.blockedUserId, 'u1');
    expect(repo.blockedLevel, 'job_posting');
    expect(repo.blockedReason, 'Spam postings');
    expect(find.widgetWithText(OutlinedButton, 'Unblock Posting'), findsOneWidget);
  });

  testWidgets('tapping Block Profile calls block with level full', (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Block Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.blockedUserId, 'u1');
    expect(repo.blockedLevel, 'full');
    expect(find.widgetWithText(OutlinedButton, 'Unblock'), findsOneWidget);
  });

  testWidgets('cancelling the block dialog does not call block', (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Block Posting'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.blockedUserId, isNull);
  });

  testWidgets('shows Unblock Posting for a job-posting-blocked account; tapping calls unblock', (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item(isJobPostingBlocked: true));
    await _pump(tester, repo);

    expect(find.widgetWithText(OutlinedButton, 'Unblock Posting'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Block Posting'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock Posting'));
    await tester.pumpAndSettle();

    expect(repo.unblockedUserId, 'u1');
    expect(repo.unblockedLevel, 'job_posting');
  });

  testWidgets('shows Unblock for a fully-blocked account; tapping calls unblock with level full', (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item(isActive: false));
    await _pump(tester, repo);

    expect(find.widgetWithText(OutlinedButton, 'Unblock'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Block Profile'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock'));
    await tester.pumpAndSettle();

    expect(repo.unblockedUserId, 'u1');
    expect(repo.unblockedLevel, 'full');
  });

  testWidgets('tapping Reset PIN, entering a 4-digit code, and confirming calls resetCode',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'New 4-digit PIN'), '1357');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset PIN'));
    await tester.pumpAndSettle();

    expect(repo.resetCodeUserId, 'u1');
    expect(repo.resetCodeValue, '1357');
    expect(find.text('PIN reset'), findsOneWidget);
  });

  testWidgets('Notes section defaults to "No notes yet."; editing and saving calls upsertNotes',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository(_item());
    await _pump(tester, repo);

    expect(find.text('No notes yet.'), findsOneWidget);

    // The Notes section's own Edit button comes after the Profile
    // section's — see the ambiguity note on the editProfile tests above.
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Internal notes about this organisation account (never shown to them)'),
        'Pending compliance document review.');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Notes'));
    await tester.pumpAndSettle();

    expect(repo.notesUserId, 'u1');
    expect(repo.notesValue, 'Pending compliance document review.');
    expect(find.text('Notes saved'), findsOneWidget);
  });
}
