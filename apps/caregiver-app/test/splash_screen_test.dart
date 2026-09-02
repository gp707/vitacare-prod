import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/core/version/app_version_repository.dart';
import 'package:caregiver_app/features/auth/screens/splash_screen.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';

class _FakeAppVersionRepository extends AppVersionRepository {
  final UpdateRequiredInfo? result;
  _FakeAppVersionRepository(this.result) : super(Dio());

  @override
  Future<UpdateRequiredInfo?> checkForUpdate() async => result;
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel? profile;
  final ApiException? error;
  _FakeProfileRepository(this.profile, {this.error}) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async {
    if (error != null) throw error!;
    if (profile == null) throw Exception('no profile');
    return profile!;
  }
}

CaregiverProfileModel _profileWithStatus(String status) => CaregiverProfileModel.fromJson({
      'user_id': 'u1',
      'profile_id': 'p1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'female',
      'age': 30,
      'languages': ['hindi'],
      'terms_accepted': true,
      'verification_status': status,
      'created_at': '2026-08-01T10:00:00Z',
    });

CaregiverProfileModel _availableProfile() => _profileWithStatus('available');

Future<void> _pumpSplash(
  WidgetTester tester, {
  required AppVersionRepository appVersionRepo,
  ProfileRepository? profileRepo,
  String? initialDeepLinkRoute,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'access_token': 'fake-token'});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        appVersionRepositoryProvider.overrideWithValue(appVersionRepo),
        if (profileRepo != null) profileRepositoryProvider.overrideWithValue(profileRepo),
      ],
      child: MaterialApp(
        home: SplashScreen(initialDeepLinkRoute: initialDeepLinkRoute),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/profile': (_) => const Scaffold(body: Text('Profile Page')),
          '/jobs': (_) => const Scaffold(body: Text('Jobs Page')),
          '/my-jobs': (_) => const Scaffold(body: Text('My Jobs Page')),
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

  testWidgets('a genuinely invalid/expired token (AUTH_005) is cleared and routes to login', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(
        null,
        error: const ApiException(code: 'AUTH_005', message: 'Invalid or expired token'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsNothing);
    expect(find.text('Login Page'), findsOneWidget);
  });

  testWidgets('a transient load failure (e.g. network/server error) fails open with a retry, not a forced logout',
      (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(
        null,
        error: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsNothing);
    expect(find.text('Login Page'), findsNothing);
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('an authenticated session restores the pre-refresh route (e.g. Jobs) instead of the default Profile',
      (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(_availableProfile()),
      initialDeepLinkRoute: '/jobs',
    );
    await tester.pumpAndSettle();

    expect(find.text('Jobs Page'), findsOneWidget);
    expect(find.text('Profile Page'), findsNothing);
  });

  testWidgets('falls back to the default route when there is no captured deep-link route', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(_availableProfile()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile Page'), findsOneWidget);
    expect(find.text('Jobs Page'), findsNothing);
  });

  testWidgets('falls back to the default route when the captured route is not restorable (e.g. "/")',
      (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(_availableProfile()),
      initialDeepLinkRoute: '/',
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile Page'), findsOneWidget);
  });

  testWidgets('an assigned caregiver (accepted to a job) lands on MyJobs on launch/refresh, not Profile',
      (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(_profileWithStatus('assigned')),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Jobs Page'), findsOneWidget);
    expect(find.text('Profile Page'), findsNothing);
  });

  testWidgets('a rejected caregiver lands on Jobs on launch/refresh, not Profile', (tester) async {
    await _pumpSplash(
      tester,
      appVersionRepo: _FakeAppVersionRepository(null),
      profileRepo: _FakeProfileRepository(_profileWithStatus('rejected')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jobs Page'), findsOneWidget);
    expect(find.text('Profile Page'), findsNothing);
  });
}
