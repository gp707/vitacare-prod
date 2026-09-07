import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/features/audit_logs/data/audit_log_models.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/audit_logs/widgets/scoped_audit_history_section.dart';

AuditLogEntry _entry({String id = 'log-1', String action = 'status_changed'}) {
  return AuditLogEntry.fromJson({
    'id': id,
    'user_id': 'admin-1',
    'user_name': 'Admin One',
    'target_user_id': 'u1',
    'target_user_name': 'Ramesh Kumar',
    'action': action,
    'entity_type': 'caregiver_profiles',
    'entity_id': 'profile-1',
    'before_value': null,
    'after_value': null,
    'ip_address': null,
    'created_at': '2026-08-17T10:00:00Z',
  });
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  List<AuditLogEntry> items;
  int total;
  int totalPages;
  AuditLogListFilters? lastFilters;
  int callCount = 0;

  _FakeAuditLogsRepository(this.items, {this.total = 1, this.totalPages = 1}) : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    callCount++;
    lastFilters = filters;
    return AuditLogListResult(
      items: items,
      meta: PaginationMeta(page: filters.page, limit: filters.limit, total: total, totalPages: totalPages),
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeAuditLogsRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [auditLogsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: ScopedAuditHistorySection(
            targetUserId: 'u1',
            itemBuilder: (context, entry) => Text(entry.action),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fetches scoped to the given targetUserId on first load', (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);

    expect(repo.lastFilters?.targetUserId, 'u1');
    expect(find.text('status_changed'), findsOneWidget);
  });

  testWidgets('shows the account-level empty message when there are no filters and no entries',
      (tester) async {
    final repo = _FakeAuditLogsRepository([]);
    await _pump(tester, repo);

    expect(find.text('No actions recorded for this account yet.'), findsOneWidget);
  });

  testWidgets('typing into Search and tapping Search re-fetches with the search term, scoped to page 1',
      (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'ADMIN-JOB-512');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, 'ADMIN-JOB-512');
    expect(repo.lastFilters?.targetUserId, 'u1');
    expect(repo.lastFilters?.page, 1);
  });

  testWidgets('submitting the Search field (Enter) also re-fetches', (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'schedule');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, 'schedule');
  });

  testWidgets('picking an Action immediately re-fetches with it, no separate Search tap needed',
      (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);
    final callsBefore = repo.callCount;

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'All actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('status_changed').last);
    await tester.pumpAndSettle();

    expect(repo.callCount, greaterThan(callsBefore));
    expect(repo.lastFilters?.action, 'status_changed');
  });

  testWidgets('shows a "no matches" message (not the account-empty message) once a filter is active',
      (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);

    repo.items = [];
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'no-such-term');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('No activity matches these filters.'), findsOneWidget);
    expect(find.text('No actions recorded for this account yet.'), findsNothing);
  });

  testWidgets('Clear resets the search text and re-fetches with no filters', (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()]);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'something');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, '');
    expect(repo.lastFilters?.action, isNull);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('shows a pager and pages forward when there is more than one page', (tester) async {
    final repo = _FakeAuditLogsRepository([_entry()], total: 45, totalPages: 3);
    await _pump(tester, repo);

    expect(find.text('Page 1 of 3 (45 total)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.page, 2);
  });
}
