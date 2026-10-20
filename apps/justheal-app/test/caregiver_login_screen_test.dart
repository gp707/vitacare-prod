import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/app/route_for_status.dart';
import 'package:nursenow_app/caregiver/core/providers.dart';
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart';
import 'package:nursenow_app/caregiver/features/auth/data/auth_repository.dart';
import 'package:nursenow_app/caregiver/features/auth/data/auth_result.dart';
import 'package:nursenow_app/caregiver/features/auth/screens/login_screen.dart';
import 'package:nursenow_app/caregiver/features/profile/data/profile_repository.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio());

  @override
  Future<AuthResult> loginCode(String phone, String code) async => const AuthResult(
        userId: 'c1',
        accessToken: 'caregiver-access',
        refreshToken: 'caregiver-refresh',
        verificationStatus: 'available',
      );
}

/// Without this override, loadSession()'s own GET /caregiver/profile call
/// hits a real (unmocked) Dio instance and falls through to
/// SessionLoadError, so `session is SessionAuthenticated` never fires and
/// the post-login navigation branch this test exists to check never runs.
class _FakeProfileRepository extends ProfileRepository {
  final String verificationStatus;

  _FakeProfileRepository({required this.verificationStatus}) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => CaregiverProfileModel(
        userId: 'c1',
        profileId: 'profile-c1',
        fullName: 'Test Caregiver',
        phone: '+919876543210',
        gender: 'female',
        age: 30,
        languages: const ['english'],
        otherDocumentUrls: const [],
        termsAccepted: true,
        verificationStatus: verificationStatus,
        preferredCities: const [],
        createdAt: DateTime(2026).toIso8601String(),
      );
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required String verificationStatus,
  required List<RouteSettings> pushedRoutes,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepository(verificationStatus: verificationStatus)),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
        onGenerateRoute: (settings) {
          pushedRoutes.add(settings);
          return MaterialPageRoute(settings: settings, builder: (_) => Scaffold(body: Text('route:${settings.name}')));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Regression: the user-reported bug was specifically "caregiver logs in
  // [via caregiver-app's own dedicated login screen, not the nursenow
  // fallback path] and if they were accepted for the job, screen defaults
  // to Profile and not [MyJobs's Selected tab]". The unified host login's
  // own fallback path already covered this correctly (see
  // login_screen_test.dart's "caregiver login fallback" group) — this file
  // specifically exercises caregiver-app's OWN /caregiver/login screen's
  // _onLoggedIn, a separate code path with its own providers.
  testWidgets('an assigned caregiver lands on MyJobs\'s Selected tab after logging in via caregiver-app\'s own '
      'login screen, not on Profile', (tester) async {
    final pushedRoutes = <RouteSettings>[];
    await _pumpLogin(tester, verificationStatus: VerificationStatus.assigned, pushedRoutes: pushedRoutes);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isNotEmpty, reason: 'expected a named push once loadSession() resolved');
    final lastRoute = pushedRoutes.last;
    expect(lastRoute.name, '/caregiver/my-jobs');
    expect(lastRoute.arguments, isA<MyAssignmentScreenArgs>());
    expect((lastRoute.arguments as MyAssignmentScreenArgs).initialTabIndex, 1);
  });

  testWidgets('an available (not assigned) caregiver lands on Profile, same as before', (tester) async {
    final pushedRoutes = <RouteSettings>[];
    await _pumpLogin(tester, verificationStatus: VerificationStatus.available, pushedRoutes: pushedRoutes);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isNotEmpty);
    expect(pushedRoutes.last.name, '/caregiver/profile');
  });

  testWidgets('a rejected caregiver lands on Jobs', (tester) async {
    final pushedRoutes = <RouteSettings>[];
    await _pumpLogin(tester, verificationStatus: VerificationStatus.rejected, pushedRoutes: pushedRoutes);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isNotEmpty);
    expect(pushedRoutes.last.name, '/caregiver/jobs');
  });

  testWidgets('a pendingCall caregiver lands on the waiting screen', (tester) async {
    final pushedRoutes = <RouteSettings>[];
    await _pumpLogin(tester, verificationStatus: VerificationStatus.pendingCall, pushedRoutes: pushedRoutes);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isNotEmpty);
    expect(pushedRoutes.last.name, '/caregiver/pending-call');
  });

  testWidgets('shows an error instead of navigating when the server error is not ApiException-shaped', (tester) async {
    // Covers the SessionLoadError branch — not the focus of this
    // regression, included for completeness since _onLoggedIn has 3
    // branches and this file otherwise only exercises SessionAuthenticated.
    final pushedRoutes = <RouteSettings>[];
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          // Deliberately NOT overriding profileRepositoryProvider — the
          // real one hits an unmocked Dio call and fails open to
          // SessionLoadError via loadSession()'s own retry logic.
        ],
        child: MaterialApp(
          home: const LoginScreen(),
          onGenerateRoute: (settings) {
            pushedRoutes.add(settings);
            return MaterialPageRoute(settings: settings, builder: (_) => Scaffold(body: Text('route:${settings.name}')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, isEmpty);
  });
}
