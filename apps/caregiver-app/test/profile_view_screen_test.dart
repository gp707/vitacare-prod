import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/profile_view_screen.dart';

CaregiverProfileModel _profile({bool advancedDetailsCompleted = false, String status = 'pending_call'}) {
  return CaregiverProfileModel.fromJson({
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
    'terms_accepted': advancedDetailsCompleted,
    'verification_status': status,
    'advanced_details_completed': advancedDetailsCompleted,
    'created_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;
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
  });

  testWidgets('professional info Edit is disabled with a hint before advanced details are completed',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(advancedDetailsCompleted: false));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete Advanced Details first'), findsNWidgets(2)); // professional info + documents
  });

  testWidgets('professional info Edit is enabled once advanced details are completed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(advancedDetailsCompleted: true, status: 'available'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete Advanced Details first'), findsNothing);
    // Basic Info + Professional & Contact Info + Documents = 3 Edit buttons
    // (Work Details has none, it's fully admin-assigned).
    expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(3));
  });

  testWidgets('shows an Edit & Resubmit button when rejected', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(advancedDetailsCompleted: true, status: 'rejected'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Edit & Resubmit'), findsOneWidget);
  });

  testWidgets('no Edit & Resubmit button when not rejected', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(advancedDetailsCompleted: true, status: 'available'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Edit & Resubmit'), findsNothing);
  });

  testWidgets('when rejected, the normal Professional Info Edit is replaced by a hint pointing to Edit & Resubmit',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(advancedDetailsCompleted: true, status: 'rejected'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileViewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Use Edit & Resubmit above'), findsNWidgets(2)); // professional info + documents
    // Only Basic Info's Edit remains as a TextButton.
    expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
  });
}
