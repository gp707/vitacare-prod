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
import 'package:admin_web/features/push_notifications/data/admin_push_notifications_repository.dart';
import 'package:admin_web/features/push_notifications/screens/push_notifications_screen.dart';

AdminPushNotificationItem _item({
  String id = 'notif-1',
  String title = 'Reminder',
  String body = 'Please update your documents',
  String status = 'pending',
  int recipientCount = 3,
}) {
  return AdminPushNotificationItem(
    id: id,
    createdByName: 'Admin One',
    title: title,
    body: body,
    scheduledAt: '2026-08-10T10:00:00Z',
    status: status,
    recipientCount: recipientCount,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminPushNotificationsRepository extends AdminPushNotificationsRepository {
  List<AdminPushNotificationItem> items;
  String? cancelledId;

  _FakeAdminPushNotificationsRepository(this.items) : super(Dio());

  @override
  Future<AdminPushNotificationsListResult> list({int page = 1, int limit = 20}) async {
    return AdminPushNotificationsListResult(
      items: items,
      meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: 1),
    );
  }

  @override
  Future<void> cancel(String id) async {
    cancelledId = id;
    items = items.where((item) => item.id != id).toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminPushNotificationsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(2200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminPushNotificationsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: PushNotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists past notifications with their status and recipient count', (tester) async {
    await _pump(tester, _FakeAdminPushNotificationsRepository([_item()]));

    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Admin One'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing has been sent yet', (tester) async {
    await _pump(tester, _FakeAdminPushNotificationsRepository([]));
    expect(find.text('No push notifications sent yet.'), findsOneWidget);
  });

  testWidgets('offers Cancel only on a pending notification, and calls the repository', (tester) async {
    final repo = _FakeAdminPushNotificationsRepository([
      _item(id: 'notif-1', status: 'pending'),
      _item(id: 'notif-2', status: 'sent'),
    ]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.cancelledId, 'notif-1');
  });
}
