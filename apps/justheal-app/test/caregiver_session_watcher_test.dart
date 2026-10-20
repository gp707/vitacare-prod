import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/app/app.dart';
import 'package:nursenow_app/caregiver/core/fcm/fcm_service.dart';
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart';
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart';
import 'package:nursenow_app/caregiver/features/profile/data/profile_repository.dart';
import 'package:nursenow_app/patient_hospital/core/navigation/navigator_key.dart';

Future<void> _pump(WidgetTester tester, LocalStorage localStorage, SessionNotifier notifier) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const CaregiverSessionWatcher(child: Scaffold(body: Text('Some Caregiver Screen'))),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login Page')),
          '/caregiver/my-jobs': (_) => const Scaffold(body: Text('MyJobs Page')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Unmounts the watcher so its Timer.periodic (cancelled in dispose) is
/// torn down before the test ends — a still-pending periodic timer fails
/// the test even though it is correctly cancelled on dispose, since
/// nothing else triggers that dispose automatically at test teardown.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

SessionNotifier _notifier(LocalStorage localStorage) =>
    SessionNotifier(localStorage, ProfileRepository(Dio()), FcmService(ProfileRepository(Dio())));

void main() {
  late LocalStorage localStorage;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'caregiver_access_token': 'fake-token'});
    localStorage = await LocalStorage.create();
  });

  testWidgets('redirects to /login the moment the session becomes unauthenticated — e.g. a mid-session token '
      'invalidation, not just at splash', (tester) async {
    final notifier = _notifier(localStorage)
      ..state = const SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.available,
        hasRequiredDocuments: true,
      );
    await _pump(tester, localStorage, notifier);

    expect(find.text('Some Caregiver Screen'), findsOneWidget);

    await notifier.logout();
    await tester.pumpAndSettle();

    expect(find.text('Login Page'), findsOneWidget);
    expect(find.text('Some Caregiver Screen'), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
      'redirects to MyJobs the moment an available caregiver gets accepted onto a job mid-session — not just at '
      'next login', (tester) async {
    final notifier = _notifier(localStorage)
      ..state = const SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.available,
        hasRequiredDocuments: true,
      );
    await _pump(tester, localStorage, notifier);

    expect(find.text('Some Caregiver Screen'), findsOneWidget);

    notifier.state = (notifier.state as SessionAuthenticated).copyWith(
      verificationStatus: VerificationStatus.assigned,
    );
    await tester.pumpAndSettle();

    expect(find.text('MyJobs Page'), findsOneWidget);
    expect(find.text('Some Caregiver Screen'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('does not redirect for a pendingCall -> assigned transition — PendingCallScreen\'s own listener '
      'owns every transition away from pendingCall, not this one', (tester) async {
    final notifier = _notifier(localStorage)
      ..state = const SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.pendingCall,
        hasRequiredDocuments: true,
      );
    await _pump(tester, localStorage, notifier);

    notifier.state = (notifier.state as SessionAuthenticated).copyWith(
      verificationStatus: VerificationStatus.assigned,
    );
    await tester.pumpAndSettle();

    expect(find.text('Some Caregiver Screen'), findsOneWidget);
    expect(find.text('MyJobs Page'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('does not navigate anywhere for an unrelated status fluctuation that never reaches assigned',
      (tester) async {
    final notifier = _notifier(localStorage)
      ..state = const SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.available,
        hasRequiredDocuments: true,
      );
    await _pump(tester, localStorage, notifier);

    notifier.state = (notifier.state as SessionAuthenticated).copyWith(
      verificationStatus: VerificationStatus.unavailable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Some Caregiver Screen'), findsOneWidget);
    expect(find.text('MyJobs Page'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('does not re-navigate on a later refresh tick that leaves verification_status already assigned',
      (tester) async {
    final notifier = _notifier(localStorage)
      ..state = const SessionAuthenticated(
        fullName: 'Nurse One',
        phone: '+919876543210',
        verificationStatus: VerificationStatus.assigned,
        hasRequiredDocuments: true,
      );
    await _pump(tester, localStorage, notifier);

    expect(find.text('Some Caregiver Screen'), findsOneWidget);

    // A fresh instance with the same (already-assigned) status, same shape
    // refreshStatus() produces on every poll tick regardless of whether
    // anything actually changed.
    notifier.state = (notifier.state as SessionAuthenticated).copyWith(
      verificationStatus: VerificationStatus.assigned,
    );
    await tester.pumpAndSettle();

    expect(find.text('Some Caregiver Screen'), findsOneWidget);
    expect(find.text('MyJobs Page'), findsNothing);

    await _unmount(tester);
  });
}
