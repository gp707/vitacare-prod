import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/profile_view_screen.dart';

CaregiverProfileModel _profile({String status = 'pending_call'}) {
  return CaregiverProfileModel.fromJson({
    'user_id': 'u1',
    'profile_id': 'p1',
    'caregiver_number': 500,
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'gender': 'male',
    'age': 30,
    'languages': ['hindi'],
    'service_modes': [],
    'work_types': [],
    'other_document_urls': [],
    'terms_accepted': true,
    'verification_status': status,
    'created_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeProfileRepository extends ProfileRepository {
  CaregiverProfileModel profile;
  bool markAvailableCalled = false;
  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<MarkAvailableResult> markAvailable() async {
    markAvailableCalled = true;
    profile = CaregiverProfileModel.fromJson({
      'user_id': profile.userId,
      'profile_id': profile.profileId,
      'full_name': profile.fullName,
      'phone': profile.phone,
      'gender': profile.gender,
      'age': profile.age,
      'languages': profile.languages,
      'service_modes': [],
      'work_types': [],
      'other_document_urls': [],
      'terms_accepted': profile.termsAccepted,
      'verification_status': 'available',
      'created_at': '2026-08-01T10:00:00Z',
    });
    return const MarkAvailableResult(verificationStatus: 'available', alreadyAvailable: false);
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows basic profile fields read-only', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('NUR-500'), findsOneWidget);
  });

  testWidgets('Edit is always available, at any verification status', (tester) async {
    for (final status in ['pending_call', 'available', 'unavailable', 'assigned', 'rejected']) {
      final fakeRepo = _FakeProfileRepository(_profile(status: status));
      await _pumpTall(
        tester,
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(home: ProfileViewScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Basic Info + Professional & Contact Info + Documents = 3 Edit
      // buttons (Work Details has none, it's fully admin-assigned).
      expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(3), reason: 'status: $status');
    }
  });

  testWidgets('rejected status shows the rejection message, still with normal Edit buttons', (tester) async {
    final profile = CaregiverProfileModel.fromJson({
      'user_id': 'u1',
      'profile_id': 'p1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'male',
      'age': 30,
      'languages': ['hindi'],
      'service_modes': [],
      'work_types': [],
      'other_document_urls': [],
      'terms_accepted': true,
      'verification_status': 'rejected',
      'rejection_message': 'Aadhaar unreadable',
      'created_at': '2026-08-01T10:00:00Z',
    });
    final fakeRepo = _FakeProfileRepository(profile);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Aadhaar unreadable'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(3));
  });

  for (final status in ['available', 'unavailable']) {
    testWidgets('shows Available for Jobs when status is $status', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(status: status));
      await _pumpTall(
        tester,
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(home: ProfileViewScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Available for Jobs'), findsOneWidget);
    });
  }

  for (final status in ['pending_call', 'rejected']) {
    testWidgets('hides Available for Jobs when status is $status', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(status: status));
      await _pumpTall(
        tester,
        ProviderScope(
          overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
          child: const MaterialApp(home: ProfileViewScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Available for Jobs'), findsNothing);
    });
  }

  testWidgets(
      'hides Available for Jobs when status is assigned — a caregiver may hold several accepted jobs, '
      "so this button can't say which one it means; MyJobs' per-job Mark Complete is the only way out now",
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'assigned'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, 'Available for Jobs'), findsNothing);
  });

  testWidgets('tapping Available for Jobs while already available shows a snackbar without calling the API',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'available'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Available for Jobs'));
    await tester.pumpAndSettle();

    expect(find.text('You are already marked as available'), findsOneWidget);
    expect(fakeRepo.markAvailableCalled, isFalse);
  });

  testWidgets('tapping Available for Jobs while unavailable calls the API and refreshes the status',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'unavailable'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Available for Jobs'));
    await tester.pumpAndSettle();

    expect(fakeRepo.markAvailableCalled, isTrue);
    expect(find.text("You're now marked as available"), findsOneWidget);
  });

  testWidgets('does not show the job poster\'s contact info (phone/call/WhatsApp) — that now lives only on MyJobs',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'assigned'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Posted by'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsNothing);
  });
}
