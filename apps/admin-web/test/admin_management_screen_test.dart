import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/admin_management/data/admin_users_repository.dart';
import 'package:admin_web/features/admin_management/screens/admin_management_screen.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';

AdminUser _admin({
  String userId = 'admin-1',
  String role = 'admin',
  bool isActive = true,
  String fullName = 'Regular Admin',
}) {
  return AdminUser(
    userId: userId,
    email: '$userId@vitacasahealth.in',
    phone: '+919999900001',
    fullName: fullName,
    role: role,
    isActive: isActive,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminUsersRepository extends AdminUsersRepository {
  List<AdminUser> admins;
  String? activatedUserId;
  String? roleUpdatedUserId;
  String? roleUpdatedTo;

  _FakeAdminUsersRepository(this.admins) : super(Dio());

  @override
  Future<List<AdminUser>> list() async => admins;

  @override
  Future<void> activate(String userId) async {
    activatedUserId = userId;
    admins = admins.map((a) => a.userId == userId ? _admin(userId: a.userId, isActive: true) : a).toList();
  }

  @override
  Future<void> updateRole(String userId, String role) async {
    roleUpdatedUserId = userId;
    roleUpdatedTo = role;
    admins = admins.map((a) => a.userId == userId ? _admin(userId: a.userId, role: role) : a).toList();
  }

  @override
  Future<void> deactivate(String userId) async {
    admins = admins.map((a) => a.userId == userId ? _admin(userId: a.userId, isActive: false) : a).toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminUsersRepository repo) async {
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
        adminUsersRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AdminManagementScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a super_admin row shows only a chip, no promote/deactivate actions', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin(role: 'super_admin', fullName: 'Existing Super Admin')]);
    await _pump(tester, repo);

    expect(find.text('Super Admin'), findsOneWidget);
    expect(find.byTooltip('Make Super Admin'), findsNothing);
    expect(find.byTooltip('Deactivate'), findsNothing);
  });

  testWidgets('an active admin shows Make Super Admin and Deactivate actions', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin()]);
    await _pump(tester, repo);

    expect(find.byTooltip('Make Super Admin'), findsOneWidget);
    expect(find.byTooltip('Deactivate'), findsOneWidget);
    expect(find.byTooltip('Activate'), findsNothing);
  });

  testWidgets('tapping Make Super Admin, confirming, calls updateRole', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin()]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Make Super Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Make Super Admin?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Make Super Admin'));
    await tester.pumpAndSettle();

    expect(repo.roleUpdatedUserId, 'admin-1');
    expect(repo.roleUpdatedTo, 'super_admin');
  });

  testWidgets('canceling the Make Super Admin dialog does not call updateRole', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin()]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Make Super Admin'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.roleUpdatedUserId, isNull);
  });

  testWidgets('a deactivated admin shows an Activate action instead of Deactivate', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin(isActive: false)]);
    await _pump(tester, repo);

    expect(find.text('Deactivated'), findsOneWidget);
    expect(find.byTooltip('Activate'), findsOneWidget);
    expect(find.byTooltip('Deactivate'), findsNothing);
  });

  testWidgets('tapping Activate calls the repository and refreshes to Active', (tester) async {
    final repo = _FakeAdminUsersRepository([_admin(isActive: false)]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Activate'));
    await tester.pumpAndSettle();

    expect(repo.activatedUserId, 'admin-1');
    expect(find.text('Active'), findsOneWidget);
  });
}
