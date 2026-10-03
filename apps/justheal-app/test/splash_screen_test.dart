import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/core/version/app_version_repository.dart';
import 'package:nursenow_app/patient_hospital/core/version/app_maintenance_repository.dart';
import 'package:nursenow_app/patient_hospital/features/auth/screens/splash_screen.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_model.dart';

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? error;
  _FakeIndividualRepository({this.error}) : super(Dio());

  @override
  Future<IndividualModel> getMe() async {
    if (error != null) throw error!;
    return const IndividualModel(
      userId: 'u1',
      fullName: 'Test Individual',
      phone: '+919876543210',
      isJobPostingBlocked: false,
    );
  }
}

class _FakeAppVersionRepository extends AppVersionRepository {
  final UpdateRequiredInfo? result;
  _FakeAppVersionRepository(this.result) : super(Dio());

  @override
  Future<UpdateRequiredInfo?> checkForUpdate() async => result;
}

class _FakeAppMaintenanceRepository extends AppMaintenanceRepository {
  final MaintenanceInfo? result;
  int callCount = 0;
  _FakeAppMaintenanceRepository(this.result) : super(Dio());

  @override
  Future<MaintenanceInfo?> checkForMaintenance() async {
    callCount++;
    return result;
  }
}

Future<void> _pumpSplash(
  WidgetTester tester, {
  String? initialDeepLinkRoute,
  bool authenticated = true,
  ApiException? getMeError,
  AppVersionRepository? appVersionRepo,
  AppMaintenanceRepository? maintenanceRepo,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(authenticated ? {'access_token': 'fake-token'} : {});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(_FakeIndividualRepository(error: getMeError)),
        appVersionRepositoryProvider.overrideWithValue(appVersionRepo ?? _FakeAppVersionRepository(null)),
        appMaintenanceRepositoryProvider.overrideWithValue(maintenanceRepo ?? _FakeAppMaintenanceRepository(null)),
      ],
      child: MaterialApp(
        home: SplashScreen(initialDeepLinkRoute: initialDeepLinkRoute),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/home': (_) => const Scaffold(body: Text('Home Page')),
          '/profile': (_) => const Scaffold(body: Text('Profile Page')),
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

  testWidgets('a genuinely invalid/expired token (AUTH_005) is cleared and routes to login', (tester) async {
    await _pumpSplash(
      tester,
      getMeError: const ApiException(code: 'AUTH_005', message: 'Invalid or expired token'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
  });

  testWidgets('a transient load failure (e.g. network/server error) fails open with a retry, not a forced logout',
      (tester) async {
    await _pumpSplash(
      tester,
      getMeError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsNothing);
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('blocks with Update Required and never navigates when an update is required', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(
        const UpdateRequiredInfo(
          storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursenow',
          message: 'Critical update needed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Critical update needed'), findsOneWidget);
    expect(find.text('Home Page'), findsNothing);
  });

  testWidgets('blocks with Under Maintenance and never navigates when maintenance is enabled', (tester) async {
    await _pumpSplash(
      tester,
      maintenanceRepo: _FakeAppMaintenanceRepository(
        const MaintenanceInfo(message: 'App is in maintenance mode, it will be available after 10am IST.'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Under Maintenance'), findsOneWidget);
    expect(find.text('App is in maintenance mode, it will be available after 10am IST.'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);
    expect(find.text('Home Page'), findsNothing);
  });

  testWidgets('maintenance takes priority over Update Required when both are true', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(const UpdateRequiredInfo(message: 'Please update.')),
      maintenanceRepo: _FakeAppMaintenanceRepository(const MaintenanceInfo(message: 'Down for maintenance.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Under Maintenance'), findsOneWidget);
    expect(find.text('Update Required'), findsNothing);
  });

  testWidgets('tapping Retry on the maintenance screen re-runs the check', (tester) async {
    final maintenanceRepo = _FakeAppMaintenanceRepository(const MaintenanceInfo(message: 'Down for maintenance.'));
    await _pumpSplash(tester, maintenanceRepo: maintenanceRepo);
    await tester.pumpAndSettle();
    expect(maintenanceRepo.callCount, 1);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(maintenanceRepo.callCount, 2);
    expect(find.text('Under Maintenance'), findsOneWidget);
  });
}
