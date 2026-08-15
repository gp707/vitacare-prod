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
}
