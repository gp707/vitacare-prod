import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/app/app.dart';
import 'package:nursenow_app/core/navigation/navigator_key.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

Future<void> _pump(WidgetTester tester, LocalStorage localStorage, SessionNotifier notifier) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const SessionWatcher(child: Scaffold(body: Text('Some Authenticated Screen'))),
        routes: {'/login': (_) => const Scaffold(body: Text('Login Page'))},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late LocalStorage localStorage;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'access_token': 'fake-token'});
    localStorage = await LocalStorage.create();
  });

  testWidgets(
      'redirects to /login the moment the session becomes unauthenticated — e.g. ApiClient reacting to an '
      'invalidated token from some unrelated screen mid-session, not just at splash', (tester) async {
    final notifier = SessionNotifier(localStorage, IndividualRepository(Dio()), OrganisationRepository(Dio()))
      ..state = const SessionAuthenticated(
        role: 'individual',
        fullName: 'Asha Patel',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );
    await _pump(tester, localStorage, notifier);

    expect(find.text('Some Authenticated Screen'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);

    // Simulates what AuthInterceptor.onUnauthorized triggers when some
    // unrelated API call comes back with AUTH_004/AUTH_005 while the user
    // is sitting on this screen, not on SplashScreen.
    await notifier.logout();
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
    expect(find.text('Some Authenticated Screen'), findsNothing);
  });

  testWidgets('does not navigate anywhere when the session stays authenticated (e.g. a profile refresh)',
      (tester) async {
    final notifier = SessionNotifier(localStorage, IndividualRepository(Dio()), OrganisationRepository(Dio()))
      ..state = const SessionAuthenticated(
        role: 'individual',
        fullName: 'Asha Patel',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );
    await _pump(tester, localStorage, notifier);

    notifier.state = const SessionAuthenticated(
      role: 'individual',
      fullName: 'Asha Patel (updated)',
      phone: '+919876543210',
      isJobPostingBlocked: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Some Authenticated Screen'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);
  });
}
