import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/edit_basic_profile_screen.dart';

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
    'terms_accepted': false,
    'verification_status': status,
    'advanced_details_completed': false,
    'created_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  bool updateBasicCalled = false;
  bool updatePhoneCalled = false;
  bool updateCodeCalled = false;
  int? capturedAge;
  List<String>? capturedLanguages;

  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<void> updateBasic({
    required int age,
    required List<String> languages,
  }) async {
    updateBasicCalled = true;
    capturedAge = age;
    capturedLanguages = languages;
  }

  @override
  Future<String> updatePhone(String phone) async {
    updatePhoneCalled = true;
    return profile.verificationStatus;
  }

  @override
  Future<void> updateCode(String code) async {
    updateCodeCalled = true;
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets("full name is shown read-only, not an editable field", (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Test Caregiver'), findsNothing);
    expect(find.textContaining('Contact the office to change your name'), findsOneWidget);
  });

  testWidgets("gender is shown read-only, not an editable field", (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Male'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('Contact the office to change your gender'), findsOneWidget);
  });

  testWidgets('no re-review warning when status is pending_call', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'pending_call'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('will send your profile back for re-review'), findsNothing);
  });

  testWidgets('shows a re-review warning on the phone section when status is available', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'available'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('will send your profile back for re-review'), findsOneWidget);
  });

  testWidgets('shows the warning when unavailable too', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'unavailable'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('will send your profile back for re-review'), findsOneWidget);
  });

  testWidgets('Save (basic section) sends age/languages only, via updateBasic', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditBasicProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.updateBasicCalled, isTrue);
    expect(fakeRepo.capturedAge, 30);
    expect(fakeRepo.capturedLanguages, ['hindi']);
    expect(fakeRepo.updatePhoneCalled, isFalse);
    expect(fakeRepo.updateCodeCalled, isFalse);
  });
}
