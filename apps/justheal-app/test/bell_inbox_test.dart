import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/app/messages_bell.dart';
import 'package:nursenow_app/patient_hospital/core/inbox/inbox_repository.dart';
import 'package:nursenow_app/patient_hospital/core/individual_messages/individual_messages_repository.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

class _FakeInbox extends InboxRepository {
  List<UserNotificationModel> items;
  final List<String> read = [];

  _FakeInbox(this.items) : super(Dio());

  @override
  Future<List<UserNotificationModel>> list() async => items;

  @override
  Future<void> markRead(String id) async {
    read.add(id);
    items = items.where((n) => n.id != id).toList();
  }
}

class _ThrowingIndividualRepository extends IndividualRepository {
  int calls = 0;
  _ThrowingIndividualRepository() : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async {
    calls++;
    return const [];
  }
}

class _Messages extends IndividualMessagesRepository {
  _Messages() : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async => const [];
}

UserNotificationModel _alert(String id, String title, String body) =>
    UserNotificationModel(id: id, title: title, body: body, route: '/home');

Future<_ThrowingIndividualRepository> _pump(WidgetTester tester, _FakeInbox inbox, {bool inboxOnly = false}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  final repo = _ThrowingIndividualRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(localStorage),
      individualRepositoryProvider.overrideWithValue(repo),
      individualMessagesRepositoryProvider.overrideWithValue(_Messages()),
      inboxRepositoryProvider.overrideWithValue(inbox),
    ],
    child: MaterialApp(home: Scaffold(appBar: AppBar(actions: [MessagesBellButton(inboxOnly: inboxOnly)]))),
  ));
  await _settle(tester);
  return repo;
}

void main() {
  testWidgets('alerts sent to the account show under the bell, with a badge for each', (tester) async {
    await _pump(tester, _FakeInbox([_alert('a1', 'Accepted', 'You were accepted'), _alert('a2', 'New Job', 'Bangalore')]));
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications));
    await _settle(tester);
    expect(find.text('Accepted — You were accepted'), findsOneWidget);
    expect(find.text('New Job — Bangalore'), findsOneWidget);
  });

  testWidgets('opening an alert and closing it marks it read on the server and takes it off the bell', (tester) async {
    final inbox = _FakeInbox([_alert('a1', 'Accepted', 'You were accepted')]);
    await _pump(tester, inbox);
    await tester.tap(find.byIcon(Icons.notifications));
    await _settle(tester);
    await tester.tap(find.text('Accepted — You were accepted'));
    await _settle(tester);
    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(inbox.read, ['a1']);
    expect(inbox.items, isEmpty);
  });

  testWidgets('an organisation\'s bell shows only its alerts and never asks for requirement messages', (tester) async {
    final inbox = _FakeInbox([_alert('o1', 'Applied', 'A caregiver applied')]);
    final repo = await _pump(tester, inbox, inboxOnly: true);
    expect(repo.calls, 0);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications));
    await _settle(tester);
    expect(find.text('Applied — A caregiver applied'), findsOneWidget);
  });

  testWidgets('no alerts and no messages: no badge', (tester) async {
    await _pump(tester, _FakeInbox([]), inboxOnly: true);
    expect(find.text('0'), findsNothing);
  });
}
