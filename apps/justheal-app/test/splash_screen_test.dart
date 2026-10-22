import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/core/version/app_version_repository.dart';
import 'package:nursenow_app/patient_hospital/core/version/app_maintenance_repository.dart';
import 'package:nursenow_app/patient_hospital/features/auth/screens/splash_screen.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_model.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/caregiver/app/route_for_status.dart' as caregiver_route;
import 'package:nursenow_app/caregiver/core/fcm/fcm_service.dart' as caregiver_fcm;
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart' as caregiver_local_storage;
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart' as caregiver_session;
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart' as caregiver_session_state;
import 'package:nursenow_app/caregiver/features/profile/data/profile_repository.dart' as caregiver_profile;

class _FakeIndividualRepository extends IndividualRepository {
  final ApiException? error;
  // When set, getMe() throws [error] on the first N calls, then succeeds —
  // simulates a transient cold-launch failure that clears up on its own.
  final int failFirstNCalls;
  int callCount = 0;
  _FakeIndividualRepository({this.error, this.failFirstNCalls = 0}) : super(Dio());

  @override
  Future<IndividualModel> getMe() async {
    callCount++;
    if (error != null && callCount <= failFirstNCalls) throw error!;
    if (error != null && failFirstNCalls == 0) throw error!;
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

/// Stands in for the caregiver flow's own SessionNotifier so the new
/// splash-screen fallback (_tryRestoreCaregiverSessionOrLogin) can be
/// exercised without it making a real GET /caregiver/profile call —
/// loadSession() just sets [result] directly, same stand-in pattern as
/// caregiver_session_watcher_test.dart's own notifier construction.
class _FakeCaregiverSessionNotifier extends caregiver_session.SessionNotifier {
  final caregiver_session_state.SessionState result;

  _FakeCaregiverSessionNotifier(caregiver_local_storage.LocalStorage localStorage, this.result)
      : super(
          localStorage,
          caregiver_profile.ProfileRepository(Dio()),
          caregiver_fcm.FcmService(caregiver_profile.ProfileRepository(Dio())),
        );

  @override
  Future<void> loadSession() async {
    state = result;
  }
}

Future<void> _pumpSplash(
  WidgetTester tester, {
  String? initialDeepLinkRoute,
  bool authenticated = true,
  ApiException? getMeError,
  int getMeFailFirstNCalls = 0,
  AppVersionRepository? appVersionRepo,
  AppMaintenanceRepository? maintenanceRepo,
  // A stored caregiver access token (or none) — exercises the fallback the
  // host's own splash now attempts once its own session resolves to
  // SessionUnauthenticated, before concluding the account is truly logged
  // out. [caregiverLoadSessionResult] is only consulted when a token is
  // also supplied — without one, the real (un-overridden) caregiver
  // SessionNotifier.loadSession() already resolves to SessionUnauthenticated
  // with no network call, exactly like production.
  String? caregiverAccessToken,
  caregiver_session_state.SessionState? caregiverLoadSessionResult,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    if (authenticated) 'access_token': 'fake-token',
    if (caregiverAccessToken != null) 'caregiver_access_token': caregiverAccessToken,
  });
  final localStorage = await LocalStorage.create();
  final caregiverLocalStorage = await caregiver_local_storage.LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(
          _FakeIndividualRepository(error: getMeError, failFirstNCalls: getMeFailFirstNCalls),
        ),
        appVersionRepositoryProvider.overrideWithValue(appVersionRepo ?? _FakeAppVersionRepository(null)),
        appMaintenanceRepositoryProvider.overrideWithValue(maintenanceRepo ?? _FakeAppMaintenanceRepository(null)),
        caregiver.localStorageProvider.overrideWithValue(caregiverLocalStorage),
        if (caregiverLoadSessionResult != null)
          caregiver_session.sessionProvider.overrideWith(
            (ref) => _FakeCaregiverSessionNotifier(caregiverLocalStorage, caregiverLoadSessionResult),
          ),
      ],
      child: MaterialApp(
        home: SplashScreen(initialDeepLinkRoute: initialDeepLinkRoute),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/home': (_) => const Scaffold(body: Text('Home Page')),
          '/profile': (_) => const Scaffold(body: Text('Profile Page')),
          '/caregiver/profile': (_) => const Scaffold(body: Text('Caregiver Profile Page')),
          '/caregiver/my-jobs': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final tabIndex = args is caregiver_route.MyAssignmentScreenArgs ? args.initialTabIndex : 0;
            return Scaffold(body: Text('Caregiver MyJobs Page (tab $tabIndex)'));
          },
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

  testWidgets(
      'when the host session is unauthenticated but a caregiver token is stored, restores the caregiver '
      'session instead of forcing a re-login — the cold-launch fallback for a force-killed caregiver app',
      (tester) async {
    await _pumpSplash(
      tester,
      authenticated: false,
      caregiverAccessToken: 'fake-caregiver-token',
      caregiverLoadSessionResult: const caregiver_session_state.SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.available,
        hasRequiredDocuments: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caregiver Profile Page'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);
  });

  testWidgets(
      'restoring a caregiver session that is currently assigned lands on MyJobs\' Selected tab, same as the '
      'caregiver\'s own routeForStatus/routeArgumentsForStatus mapping used elsewhere', (tester) async {
    await _pumpSplash(
      tester,
      authenticated: false,
      caregiverAccessToken: 'fake-caregiver-token',
      caregiverLoadSessionResult: const caregiver_session_state.SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.assigned,
        hasRequiredDocuments: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caregiver MyJobs Page (tab 1)'), findsOneWidget);
    expect(find.text('Login Page'), findsNothing);
  });

  testWidgets(
      'falls back to Login when a stored caregiver token exists but is rejected as invalid/expired '
      '(mirrors the existing "genuinely invalid token" behavior, just via the caregiver fallback path)',
      (tester) async {
    await _pumpSplash(
      tester,
      authenticated: false,
      caregiverAccessToken: 'fake-caregiver-token',
      caregiverLoadSessionResult: const caregiver_session_state.SessionUnauthenticated(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
  });

  testWidgets(
      'falls back to Login when a stored caregiver token exists but loading it hits a transient/load error — '
      'never strands the user on the splash screen', (tester) async {
    await _pumpSplash(
      tester,
      authenticated: false,
      caregiverAccessToken: 'fake-caregiver-token',
      caregiverLoadSessionResult: const caregiver_session_state.SessionLoadError('Could not reach the server.'),
    );
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

  testWidgets('a persistent load failure (e.g. network/server error) fails open with a retry, not a forced logout',
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

  testWidgets(
      'a transient load failure that clears up within SessionNotifier\'s own retries never surfaces the error screen',
      (tester) async {
    await _pumpSplash(
      tester,
      getMeError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
      // Fails the first 2 attempts (e.g. network/DNS not ready yet right
      // after a cold launch), succeeds on the 3rd — exactly what
      // SessionNotifier.loadSession's own silent retry loop is for.
      getMeFailFirstNCalls: 2,
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsNothing);
    expect(find.text('Home Page'), findsOneWidget);
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
