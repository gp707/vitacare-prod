import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/screens/splash_screen.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/data/individual_model.dart';

class _FakeIndividualRepository extends IndividualRepository {
  _FakeIndividualRepository() : super(Dio());

  @override
  Future<IndividualModel> getMe() async => const IndividualModel(
        userId: 'u1',
        fullName: 'Test Individual',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );
}

Future<void> _pumpSplash(WidgetTester tester, {String? initialDeepLinkRoute, bool authenticated = true}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(authenticated ? {'access_token': 'fake-token'} : {});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(_FakeIndividualRepository()),
      ],
      child: MaterialApp(
        home: SplashScreen(initialDeepLinkRoute: initialDeepLinkRoute),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/home': (_) => const Scaffold(body: Text('Home Page')),
          '/profile': (_) => const Scaffold(body: Text('Profile Page')),
          '/post-requirement': (_) => const Scaffold(body: Text('Post Requirement Page')),
        },
      ),
    ),
  );
}

void main() {
  testWidgets('unauthenticated session navigates to Login', (tester) async {
    await _pumpSplash(tester, authenticated: false);
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
  });

  testWidgets('an authenticated session restores the pre-refresh route (e.g. Profile) instead of the default Home',
      (tester) async {
    await _pumpSplash(tester, initialDeepLinkRoute: '/profile');
    await tester.pumpAndSettle();

    expect(find.text('Profile Page'), findsOneWidget);
    expect(find.text('Home Page'), findsNothing);
  });

  testWidgets('falls back to the default home route when there is no captured deep-link route', (tester) async {
    await _pumpSplash(tester);
    await tester.pumpAndSettle();

    expect(find.text('Home Page'), findsOneWidget);
  });

  testWidgets('an individual session ignores an organisation-only captured route (role mismatch) and falls back',
      (tester) async {
    await _pumpSplash(tester, initialDeepLinkRoute: '/org-home');
    await tester.pumpAndSettle();

    // '/org-home' isn't even registered in this test's route table (it's
    // organisation-only), so if the mismatch guard failed to fall back,
    // this would throw instead of showing Home Page.
    expect(find.text('Home Page'), findsOneWidget);
  });
}
