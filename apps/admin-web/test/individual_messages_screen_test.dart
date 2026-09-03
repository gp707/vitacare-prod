import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/individual_messages/data/individual_messages_repository.dart';
import 'package:admin_web/features/individual_messages/screens/individual_messages_screen.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';

IndividualMessageModel _message({
  String id = 'msg-1',
  String event = MessageEvent.requirementLive,
  String icon = MessageIcon.editNote,
  String message = 'You can edit this job and change salary.',
  int displayOrder = 10,
  bool enabled = true,
}) =>
    IndividualMessageModel(
      id: id,
      event: event,
      icon: icon,
      message: message,
      displayOrder: displayOrder,
      enabled: enabled,
    );

class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  List<IndividualMessageModel> messages;
  IndividualMessageModel? created;
  String? updatedId;
  IndividualMessageModel? updatedWith;
  String? deletedId;

  _FakeIndividualMessagesRepository(this.messages) : super(Dio());

  @override
  Future<List<IndividualMessageModel>> list() async => messages;

  @override
  Future<void> create(IndividualMessageModel message) async {
    created = message;
    messages = [...messages, IndividualMessageModel(id: 'new-id', event: message.event, icon: message.icon, message: message.message, displayOrder: message.displayOrder, enabled: message.enabled)];
  }

  @override
  Future<void> update(String id, IndividualMessageModel message) async {
    updatedId = id;
    updatedWith = message;
    messages = messages
        .map((m) => m.id == id
            ? IndividualMessageModel(
                id: id,
                event: message.event,
                icon: message.icon,
                message: message.message,
                displayOrder: message.displayOrder,
                enabled: message.enabled,
              )
            : m)
        .toList();
  }

  @override
  Future<void> delete(String id) async {
    deletedId = id;
    messages = messages.where((m) => m.id != id).toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeIndividualMessagesRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'super-1', role: 'super_admin'),
        ),
        individualMessagesRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: IndividualMessagesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every message row with event, order, and text', (tester) async {
    final repo = _FakeIndividualMessagesRepository([
      _message(id: 'm1', message: 'Edit tip', displayOrder: 10),
      _message(id: 'm2', event: MessageEvent.welcome, message: 'Welcome tip', displayOrder: 20, enabled: false),
    ]);
    await _pump(tester, repo);

    expect(find.text('Edit tip'), findsOneWidget);
    expect(find.text('Welcome tip'), findsOneWidget);
    expect(find.text('Order: 10'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state with no messages', (tester) async {
    final repo = _FakeIndividualMessagesRepository([]);
    await _pump(tester, repo);

    expect(find.text('No messages yet.'), findsOneWidget);
  });

  testWidgets('tapping Add Message, filling in text, and Save calls create and refreshes the list',
      (tester) async {
    final repo = _FakeIndividualMessagesRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Message'));
    await tester.pumpAndSettle();
    expect(find.text('Add Message'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Message').first, 'A brand new tip');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.created?.message, 'A brand new tip');
    expect(repo.created?.event, MessageEvent.requirementLive);
    expect(find.text('A brand new tip'), findsOneWidget);
  });

  testWidgets('rejects Save with an empty message, without calling create', (tester) async {
    final repo = _FakeIndividualMessagesRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Message'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.created, isNull);
    expect(find.textContaining('required'), findsOneWidget);
  });

  testWidgets('tapping Edit, changing the message, and Save calls update with the same id', (tester) async {
    final repo = _FakeIndividualMessagesRepository([_message(id: 'm1', message: 'Original text')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Message'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Message').first, 'Edited text');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.updatedId, 'm1');
    expect(repo.updatedWith?.message, 'Edited text');
    expect(find.text('Edited text'), findsOneWidget);
    expect(find.text('Original text'), findsNothing);
  });

  testWidgets('tapping Delete, confirming, calls delete and removes the row', (tester) async {
    final repo = _FakeIndividualMessagesRepository([_message(id: 'm1', message: 'To be removed')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this message?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedId, 'm1');
    expect(find.text('To be removed'), findsNothing);
    expect(find.text('No messages yet.'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation does not call delete', (tester) async {
    final repo = _FakeIndividualMessagesRepository([_message(id: 'm1', message: 'Stays put')]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deletedId, isNull);
    expect(find.text('Stays put'), findsOneWidget);
  });
}
