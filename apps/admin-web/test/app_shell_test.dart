import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/shared/widgets/app_shell.dart';

Future<void> _pumpShellAs(WidgetTester tester, String role) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: role),
        ),
      ],
      child: const MaterialApp(
        home: AppShell(current: AppShellSection.dashboard, child: SizedBox()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows Admin Management for a super_admin session', (tester) async {
    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Admin Management'), findsOneWidget);
  });

  testWidgets('hides Admin Management for a regular admin session', (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Admin Management'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Caregivers'), findsOneWidget);
  });

  testWidgets('shows Audit Logs for both admin and super_admin sessions', (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Audit Logs'), findsOneWidget);

    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Audit Logs'), findsOneWidget);
  });
}
