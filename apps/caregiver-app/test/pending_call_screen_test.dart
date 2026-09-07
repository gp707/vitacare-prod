import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/auth/state/session_notifier.dart';
import 'package:caregiver_app/features/auth/state/session_state.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/registration/screens/pending_call_screen.dart';

class _FakeProfileRepository extends ProfileRepository {
  String verificationStatus;
  int callCount = 0;
  bool throwOnCall = false;

  _FakeProfileRepository(this.verificationStatus) : super(Dio());

  @override
  Future<VerificationStatusResult> getVerificationStatus() async {
    callCount++;
    if (throwOnCall) {
      throw const ApiException(code: 'GEN_003', message: 'Could not reach the server.');
    }
    return VerificationStatusResult(verificationStatus: verificationStatus);
  }
}

const _pendingSession = SessionAuthenticated(
  fullName: 'Asha Patel',
  phone: '+919876543210',
  verificationStatus: VerificationStatus.pendingCall,
  hasRequiredDocuments: true,
);

Future<void> _pump(WidgetTester tester, _FakeProfileRepository profileRepo) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'access_token': 'fake-token'});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        profileRepositoryProvider.overrideWithValue(profileRepo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, profileRepo, ref.watch(fcmServiceProvider))..state = _pendingSession,
        ),
      ],
      child: MaterialApp(
        home: const PendingCallScreen(),
        routes: {
          '/profile': (_) => const Scaffold(body: Text('Profile Page')),
          '/jobs': (_) => const Scaffold(body: Text('Jobs Page')),
          '/my-jobs': (_) => const Scaffold(body: Text('My Jobs Page')),
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('auto-polls every 15s and navigates away the moment admin approval is picked up, with no user action',
      (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.pendingCall);
    await _pump(tester, profileRepo);

    expect(find.textContaining('Thank you for registering'), findsOneWidget);
    expect(profileRepo.callCount, 0);

    // Simulate the admin approving in between two poll ticks.
    profileRepo.verificationStatus = VerificationStatus.available;

    await tester.pump(const Duration(seconds: 15));
    expect(profileRepo.callCount, 1);
    await tester.pumpAndSettle();

    expect(find.text('Profile Page'), findsOneWidget);
    expect(find.textContaining('Thank you for registering'), findsNothing);
  });

  testWidgets('keeps polling (and staying put) while still pending_call', (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.pendingCall);
    await _pump(tester, profileRepo);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));

    expect(profileRepo.callCount, 3);
    expect(find.textContaining('Thank you for registering'), findsOneWidget);
  });

  testWidgets('a failed background poll tick is silent — no snackbar, no crash, just tries again next tick',
      (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.pendingCall)..throwOnCall = true;
    await _pump(tester, profileRepo);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(profileRepo.callCount, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Thank you for registering'), findsOneWidget);
  });

  testWidgets('pulling to refresh manually also picks up approval immediately, without waiting for the poll',
      (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.available);
    await _pump(tester, profileRepo);

    await tester.fling(find.text('Pull down to refresh'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Profile Page'), findsOneWidget);
  });

  testWidgets('a failed manual pull-to-refresh shows an error snackbar, unlike a background poll', (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.pendingCall)..throwOnCall = true;
    await _pump(tester, profileRepo);

    await tester.fling(find.text('Pull down to refresh'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Could not check for updates. Please check your connection and try again.'), findsOneWidget);

    // Drain the still-pending 5s auto-dismiss timer so the test doesn't
    // end with a live Timer outliving the widget tree.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('stops polling once the timer is disposed (no lingering timer error after leaving the screen)',
      (tester) async {
    final profileRepo = _FakeProfileRepository(VerificationStatus.pendingCall);
    await _pump(tester, profileRepo);

    // Navigate away, then let the app tear the timer down cleanly.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Elsewhere'))));
    await tester.pumpAndSettle();

    // If the Timer weren't cancelled in dispose(), pumping past its next
    // tick here with the PendingCallScreen gone would throw/fail the test.
    await tester.pump(const Duration(seconds: 15));
  });
}
