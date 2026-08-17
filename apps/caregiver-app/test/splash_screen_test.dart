import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/core/version/app_version_repository.dart';
import 'package:caregiver_app/features/auth/screens/splash_screen.dart';

class _FakeAppVersionRepository extends AppVersionRepository {
  final UpdateRequiredInfo? result;
  _FakeAppVersionRepository(this.result) : super(Dio());

  @override
  Future<UpdateRequiredInfo?> checkForUpdate() async => result;
}

Future<void> _pumpSplash(WidgetTester tester, {required AppVersionRepository appVersionRepo}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        appVersionRepositoryProvider.overrideWithValue(appVersionRepo),
      ],
      child: MaterialApp(
        home: const SplashScreen(),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
        },
      ),
    ),
  );
}

void main() {
  testWidgets('blocks with Update Required and never navigates when an update is required', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(
        const UpdateRequiredInfo(
          storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
          message: 'Critical update needed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Critical update needed'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);
  });

  testWidgets('proceeds to the normal session flow (unauthenticated -> login) when no update is required',
      (tester) async {
    await _pumpSplash(tester, appVersionRepo: _FakeAppVersionRepository(null));
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsNothing);
    expect(find.text('Login Page'), findsOneWidget);
  });
}
