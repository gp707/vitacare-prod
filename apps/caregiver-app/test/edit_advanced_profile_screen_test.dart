import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/edit_advanced_profile_screen.dart';

CaregiverProfileModel _profile({String status = 'available'}) {
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
    'advanced_details_completed': true,
    'created_at': '2026-08-01T10:00:00Z',
    'selfie_photo_url': 'https://signed/selfie',
    'aadhaar_document_url': 'https://signed/aadhaar',
    'highest_qualification': 'bsc_gnm_completed',
    'religion': 'hindu',
    'current_address': '123 Old Street',
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  bool editAdvancedProfileCalled = false;
  Map<String, dynamic> captured = {};

  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<void> editAdvancedProfile({
    String? highestQualification,
    String? fatherName,
    String? fatherPhone,
    String? currentAddress,
    List<String>? preferredCities,
    String? notes,
  }) async {
    editAdvancedProfileCalled = true;
    captured = {
      'highestQualification': highestQualification,
      'fatherName': fatherName,
      'fatherPhone': fatherPhone,
      'currentAddress': currentAddress,
      'preferredCities': preferredCities,
      'notes': notes,
    };
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows an Aadhaar re-review warning when status is available', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'available'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditAdvancedProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Re-uploading your Aadhaar card will send your profile back for re-review'),
        findsOneWidget);
  });

  testWidgets('no Aadhaar warning when status is pending_verification', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'pending_verification'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditAdvancedProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Re-uploading your Aadhaar card will send your profile back for re-review'),
        findsNothing);
  });

  testWidgets('Save sends only the field that actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditAdvancedProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Current Address'), '456 New Street');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.editAdvancedProfileCalled, isTrue);
    expect(fakeRepo.captured['currentAddress'], '456 New Street');
    expect(fakeRepo.captured['highestQualification'], isNull);
    expect(fakeRepo.captured['fatherName'], isNull);
    expect(fakeRepo.captured['preferredCities'], isNull);
  });

  testWidgets('religion is shown read-only, not an editable field', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditAdvancedProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Religion.displayNames[Religion.hindu]!), findsOneWidget);
    expect(find.textContaining('Contact the office to change your religion'), findsOneWidget);
  });

  testWidgets('Save sends preferredCities only when the selection actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditAdvancedProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bangalore'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.captured['preferredCities'], ['bangalore']);
  });
}
