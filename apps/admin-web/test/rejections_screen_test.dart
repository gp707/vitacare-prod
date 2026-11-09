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
import 'package:admin_web/features/rejections/data/admin_rejections_repository.dart';
import 'package:admin_web/features/rejections/screens/rejections_screen.dart';

AdminRejectionItem _item({
  String event = 'poster_rejected',
  String? reason = 'Required Tamil speaking caretaker',
  String caregiverName = 'Afchana Akter',
  String? decidedByName = 'Rani Sukumar',
  String? decidedByRole = 'individual',
}) {
  return AdminRejectionItem(
    kind: 'job',
    applicationId: 'a1',
    event: event,
    occurredAt: '2026-11-05T10:00:00Z',
    reason: reason,
    caregiverProfileId: 'p1',
    caregiverNumber: 512,
    caregiverName: caregiverName,
    caregiverPhone: '+919876543210',
    patientJobNumber: 520,
    posterName: 'Rani Sukumar',
    posterRole: 'individual',
    posterNumber: 505,
    decidedByName: decidedByName,
    decidedByRole: decidedByRole,
  );
}

class _FakeRepo extends AdminRejectionsRepository {
  final List<AdminRejectionItem> items;
  String? lastDirection;

  _FakeRepo(this.items) : super(Dio());

  @override
  Future<AdminRejectionsListResult> list({int page = 1, int limit = 20, String? direction, String? search}) async {
    lastDirection = direction;
    return AdminRejectionsListResult(
      items: items,
      meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: 1),
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  await tester.binding.setSurfaceSize(const Size(1800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminRejectionsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: RejectionsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows who rejected the caregiver, the job and the reason', (tester) async {
    await _pump(tester, _FakeRepo([_item()]));

    expect(find.text('Rejected caregiver'), findsOneWidget);
    expect(find.text('Required Tamil speaking caretaker'), findsOneWidget);
    expect(find.textContaining('NUR-512'), findsOneWidget);
    expect(find.text('PAT-JOB-520'), findsOneWidget);
    expect(find.text('Rani Sukumar'), findsWidgets);
  });

  testWidgets('a caregiver decline says no reason is collected', (tester) async {
    await _pump(tester, _FakeRepo([_item(event: 'caregiver_declined', reason: null, decidedByName: null)]));

    expect(find.text('Caregiver declined'), findsOneWidget);
    expect(find.text('No reason is asked when a caregiver declines'), findsOneWidget);
  });

  testWidgets('a caregiver close shows the readable close reason', (tester) async {
    await _pump(tester, _FakeRepo([_item(event: 'caregiver_closed', reason: 'family_problems', decidedByName: null)]));

    expect(find.text('Caregiver closed job'), findsOneWidget);
    expect(find.text('Family problems'), findsOneWidget);
  });

  testWidgets('an admin rejection is labelled as admin', (tester) async {
    await _pump(tester, _FakeRepo([_item(decidedByName: 'Veer', decidedByRole: 'admin')]));
    expect(find.text('Veer (admin)'), findsOneWidget);
  });

  testWidgets('shows an empty state', (tester) async {
    await _pump(tester, _FakeRepo([]));
    expect(find.text('No rejections match this filter.'), findsOneWidget);
  });
}
