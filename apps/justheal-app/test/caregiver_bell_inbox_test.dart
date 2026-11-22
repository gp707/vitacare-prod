import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/app/messages_bell.dart';
import 'package:nursenow_app/caregiver/core/caregiver_messages/caregiver_messages_repository.dart';
import 'package:nursenow_app/caregiver/core/inbox/inbox_repository.dart';
import 'package:nursenow_app/caregiver/core/providers.dart';
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart';
import 'package:nursenow_app/caregiver/features/jobs/data/jobs_repository.dart';

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

class _Jobs extends JobsRepository {
  _Jobs() : super(Dio());
  @override
  Future<List<JobModel>> listActiveJobs() async => const [];
  @override
  Future<List<JobModel>> getAssignedJobs() async => const [];
}

class _Messages extends CaregiverMessagesRepository {
  _Messages() : super(Dio());
  @override
  Future<List<CaregiverMessageModel>> get() async => const [];
}

void main() {
  testWidgets('a caregiver\'s alerts show under the bell and leave it once read', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final inbox = _FakeInbox([UserNotificationModel(id: 'c1', title: 'New Job', body: 'Bangalore', route: '/caregiver/jobs')]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        jobsRepositoryProvider.overrideWithValue(_Jobs()),
        caregiverMessagesRepositoryProvider.overrideWithValue(_Messages()),
        inboxRepositoryProvider.overrideWithValue(inbox),
      ],
      child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [MessagesBellButton()]))),
    ));
    await _settle(tester);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications));
    await _settle(tester);
    await tester.tap(find.text('New Job — Bangalore'));
    await _settle(tester);
    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(inbox.read, ['c1']);
    expect(inbox.items, isEmpty);
  });
}
