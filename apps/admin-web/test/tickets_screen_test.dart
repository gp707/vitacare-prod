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
import 'package:admin_web/features/tickets/data/admin_tickets_repository.dart';
import 'package:admin_web/features/tickets/screens/tickets_screen.dart';

AdminTicketItem _item({
  String id = 'ticket-1',
  String userId = 'u1',
  String userFullName = 'Ramesh Kumar',
  String userRole = 'caregiver',
  int? caregiverNumber = 500,
  String status = 'open',
}) {
  return AdminTicketItem(
    id: id,
    userId: userId,
    userFullName: userFullName,
    userRole: userRole,
    caregiverNumber: caregiverNumber,
    caregiverProfileId: 'profile-1',
    type: 'forgot_pin',
    status: status,
    phone: '+919876543210',
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminTicketsRepository extends AdminTicketsRepository {
  List<AdminTicketItem> items;
  String? resolvedId;
  String? resolvedNotes;
  String? lastStatusFilter;

  _FakeAdminTicketsRepository(this.items) : super(Dio());

  @override
  Future<AdminTicketsListResult> list({int page = 1, int limit = 20, String? status}) async {
    lastStatusFilter = status;
    final filtered = status == null ? items : items.where((i) => i.status == status).toList();
    return AdminTicketsListResult(
      items: filtered,
      meta: PaginationMeta(page: 1, limit: 20, total: filtered.length, totalPages: 1),
    );
  }

  @override
  Future<void> resolve(String id, {String? notes}) async {
    resolvedId = id;
    resolvedNotes = notes;
    items = items.map((i) => i.id == id
        ? AdminTicketItem(
            id: i.id,
            userId: i.userId,
            userFullName: i.userFullName,
            userRole: i.userRole,
            caregiverNumber: i.caregiverNumber,
            caregiverProfileId: i.caregiverProfileId,
            type: i.type,
            status: 'resolved',
            phone: i.phone,
            createdAt: i.createdAt,
          )
        : i).toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminTicketsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(1800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminTicketsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: TicketsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the Open filter and lists open tickets with requester info', (tester) async {
    final repo = _FakeAdminTicketsRepository([_item()]);
    await _pump(tester, repo);

    expect(repo.lastStatusFilter, 'open');
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('NUR-500'), findsOneWidget);
    expect(find.text('Forgot PIN'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no matching tickets', (tester) async {
    await _pump(tester, _FakeAdminTicketsRepository([]));
    expect(find.text('No tickets match this filter.'), findsOneWidget);
  });

  testWidgets('resolving an open ticket opens a notes dialog and calls the repository', (tester) async {
    final repo = _FakeAdminTicketsRepository([_item()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Resolve'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Resolution notes (optional)'), 'Called and verified.');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Resolve').last);
    await tester.pumpAndSettle();

    expect(repo.resolvedId, 'ticket-1');
    expect(repo.resolvedNotes, 'Called and verified.');
  });

  testWidgets('a resolved ticket shows no Resolve action', (tester) async {
    final repo = _FakeAdminTicketsRepository([_item(status: 'resolved')]);
    await _pump(tester, repo);

    // Switch the filter to see resolved tickets (default filter is Open).
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Resolve'), findsNothing);
  });
}
