import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/app/root_screen.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';

/// loadSession() normally decodes the stored JWT — overridden here to just
/// set a canned result directly, so the test controls the resolved session
/// state without needing a real token.
class _FakeSessionNotifier extends SessionNotifier {
  final AdminSessionState result;
  _FakeSessionNotifier(this.result, super.localStorage);

  @override
  Future<void> loadSession() async {
    state = result;
  }
}

Future<void> _pumpRoot(
  WidgetTester tester, {
  required AdminSessionState sessionResult,
  String? initialDeepLinkRoute,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
            (ref) => _FakeSessionNotifier(sessionResult, localStorage)),
      ],
      child: MaterialApp(
        home: RootScreen(initialDeepLinkRoute: initialDeepLinkRoute),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/dashboard': (_) => const Scaffold(body: Text('Dashboard Page')),
          '/jobs': (_) => const Scaffold(body: Text('Jobs Page')),
          '/patients-family': (_) =>
              const Scaffold(body: Text('Patients Family Page')),
          '/reports': (_) => const Scaffold(body: Text('Reports Page')),
        },
      ),
    ),
  );
}

void main() {
  testWidgets('unauthenticated session navigates to Login', (tester) async {
    await _pumpRoot(tester, sessionResult: const AdminSessionUnauthenticated());
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
  });

  testWidgets(
      'an authenticated session restores the pre-refresh route (e.g. Jobs) instead of the default Dashboard',
      (tester) async {
    await _pumpRoot(
      tester,
      sessionResult:
          const AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
      initialDeepLinkRoute: '/jobs',
    );
    await tester.pumpAndSettle();

    expect(find.text('Jobs Page'), findsOneWidget);
    expect(find.text('Dashboard Page'), findsNothing);
  });

  testWidgets(
      'restores /patients-family too, proving this is not just special-cased for /jobs',
      (tester) async {
    await _pumpRoot(
      tester,
      sessionResult:
          const AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
      initialDeepLinkRoute: '/patients-family',
    );
    await tester.pumpAndSettle();

    expect(find.text('Patients Family Page'), findsOneWidget);
  });

  testWidgets(
      'restores /reports too — refreshing while on the Reports screen must not bounce to Dashboard',
      (tester) async {
    await _pumpRoot(
      tester,
      sessionResult:
          const AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
      initialDeepLinkRoute: '/reports',
    );
    await tester.pumpAndSettle();

    expect(find.text('Reports Page'), findsOneWidget);
    expect(find.text('Dashboard Page'), findsNothing);
  });

  testWidgets(
      'falls back to the default Dashboard when there is no captured deep-link route',
      (tester) async {
    await _pumpRoot(tester,
        sessionResult:
            const AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard Page'), findsOneWidget);
  });

  testWidgets(
      'falls back to the default Dashboard when the captured route requires an argument we don\'t have '
      '(e.g. /caregiver-detail)', (tester) async {
    await _pumpRoot(
      tester,
      sessionResult:
          const AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
      initialDeepLinkRoute: '/caregiver-detail',
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard Page'), findsOneWidget);
  });
}
