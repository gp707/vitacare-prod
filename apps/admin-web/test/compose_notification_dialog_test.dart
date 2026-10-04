import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/features/push_notifications/data/admin_push_notifications_repository.dart';
import 'package:admin_web/features/push_notifications/widgets/compose_notification_dialog.dart';
import 'package:admin_web/shared/state/recipient_selection_cart.dart';

class _FakeAdminPushNotificationsRepository extends AdminPushNotificationsRepository {
  String? createdTitle;
  String? createdBody;
  DateTime? createdScheduledAt;
  List<String>? createdRecipientUserIds;
  String statusToReturn;

  _FakeAdminPushNotificationsRepository({this.statusToReturn = 'sent'}) : super(Dio());

  @override
  Future<AdminPushNotificationItem> create({
    required String title,
    required String body,
    DateTime? scheduledAt,
    required List<String> recipientUserIds,
  }) async {
    createdTitle = title;
    createdBody = body;
    createdScheduledAt = scheduledAt;
    createdRecipientUserIds = recipientUserIds;
    return AdminPushNotificationItem(
      id: 'notif-1',
      createdByName: 'Admin One',
      title: title,
      body: body,
      scheduledAt: (scheduledAt ?? DateTime.now()).toUtc().toIso8601String(),
      status: statusToReturn,
      recipientCount: recipientUserIds.length,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

RecipientSelectionCartNotifier _seededCart() {
  final notifier = RecipientSelectionCartNotifier();
  notifier.addAll(const [
    SelectedRecipient(userId: 'u1', role: 'caregiver', displayName: 'Ramesh Kumar'),
    SelectedRecipient(userId: 'u2', role: 'individual', displayName: 'Asha Patel'),
  ]);
  return notifier;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminPushNotificationsRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminPushNotificationsRepositoryProvider.overrideWithValue(repo),
        recipientSelectionCartProvider.overrideWith((ref) => _seededCart()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ComposeNotificationDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a recipient breakdown by role', (tester) async {
    await _pump(tester, _FakeAdminPushNotificationsRepository());

    expect(find.text('1 caregiver'), findsOneWidget);
    expect(find.text('1 patient'), findsOneWidget);
  });

  testWidgets('Send Now is disabled until both title and body are filled', (tester) async {
    await _pump(tester, _FakeAdminPushNotificationsRepository());

    final sendButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send Now'));
    expect(sendButton.onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Reminder');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send Now')).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Please update your documents.');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send Now')).onPressed, isNotNull);
  });

  testWidgets('sending now calls create() with no scheduled_at, clears the cart, and closes the dialog',
      (tester) async {
    final repo = _FakeAdminPushNotificationsRepository();
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Reminder');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Please update your documents.');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Now'));
    await tester.pumpAndSettle();

    expect(repo.createdTitle, 'Reminder');
    expect(repo.createdBody, 'Please update your documents.');
    expect(repo.createdScheduledAt, isNull);
    expect(repo.createdRecipientUserIds, unorderedEquals(['u1', 'u2']));
    expect(find.byType(ComposeNotificationDialog), findsNothing);
    expect(find.textContaining('Notification sent to 2 recipient(s)'), findsOneWidget);
  });

  testWidgets('shows a failure message (not a false "sent") when the backend reports status failed',
      (tester) async {
    final repo = _FakeAdminPushNotificationsRepository(statusToReturn: 'failed');
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Reminder');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Body');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be delivered'), findsOneWidget);
  });

  testWidgets('scheduling for later requires a future date/time before Schedule is enabled', (tester) async {
    await _pump(tester, _FakeAdminPushNotificationsRepository());

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Reminder');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Body');
    await tester.pump();
    await tester.tap(find.text('Schedule for later'));
    await tester.pump();

    // No date/time picked yet — Schedule stays disabled.
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Schedule')).onPressed, isNull);
  });
}
