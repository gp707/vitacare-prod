import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/edit_profile_screen.dart';

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
    'created_at': '2026-08-01T10:00:00Z',
    'selfie_photo_url': 'https://signed/selfie',
    'aadhaar_document_url': 'https://signed/aadhaar',
    'highest_qualification': 'rn_above_2_years',
    'religion': 'hindu',
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  bool editProfileCalled = false;
  Map<String, dynamic> captured = {};
  String editProfileReturnStatus;

  _FakeProfileRepository(this.profile, {this.editProfileReturnStatus = 'available'}) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<String> editProfile({
    int? age,
    List<String>? languages,
    String? highestQualification,
    List<String>? preferredCities,
    List<String>? preferredDutyTypes,
    int? minSalaryPerDay,
    int? minSalaryPerMonth,
  }) async {
    editProfileCalled = true;
    captured = {
      'age': age,
      'languages': languages,
      'highestQualification': highestQualification,
      'preferredCities': preferredCities,
      'preferredDutyTypes': preferredDutyTypes,
      'minSalaryPerDay': minSalaryPerDay,
      'minSalaryPerMonth': minSalaryPerMonth,
    };
    return editProfileReturnStatus;
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
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Changing your phone number will send your profile back for re-review'),
        findsOneWidget);
  });

  testWidgets('no Aadhaar re-review warning when status is pending_call', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'pending_call'));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Changing your phone number will send your profile back for re-review'),
        findsNothing);
  });

  testWidgets('full name, gender, and religion are shown read-only', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('Contact the office to change your name.'), findsOneWidget);
    expect(find.text('Contact the office to change your gender.'), findsOneWidget);
    expect(find.text(Religion.displayNames[Religion.hindu]!), findsOneWidget);
    expect(find.text('Contact the office to change your religion.'), findsOneWidget);
  });

  testWidgets('Save sends only the field that actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Qualification.displayNames[Qualification.rnBelow2Years]!).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.editProfileCalled, isTrue);
    expect(fakeRepo.captured['highestQualification'], Qualification.rnBelow2Years);
    expect(fakeRepo.captured['age'], isNull);
    expect(fakeRepo.captured['languages'], isNull);
    expect(fakeRepo.captured['preferredCities'], isNull);
    expect(fakeRepo.captured['preferredDutyTypes'], isNull);
    expect(fakeRepo.captured['minSalaryPerDay'], isNull);
    expect(fakeRepo.captured['minSalaryPerMonth'], isNull);
  });

  testWidgets('Save sends age when changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Age'), '31');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.captured['age'], 31);
  });

  testWidgets('Save sends preferredCities only when the selection actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bangalore'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.captured['preferredCities'], ['bangalore']);
  });

  testWidgets('Save sends preferredDutyTypes only when the selection actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, DutyType.displayNames[DutyType.dayDuty]!));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.captured['preferredDutyTypes'], [DutyType.dayDuty]);
  });

  testWidgets('Save sends min salary fields only when actually changed', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Minimum Salary — ₹/day (optional)'), '1500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.captured['minSalaryPerDay'], 1500);
    expect(fakeRepo.captured['minSalaryPerMonth'], isNull);
  });

  testWidgets('rejects a non-numeric minimum salary without calling the repository', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Minimum Salary — ₹/day (optional)'), 'abc');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.editProfileCalled, isFalse);
    expect(find.text('Minimum salary per day must be a positive number'), findsOneWidget);
  });

  testWidgets('editing while rejected shows the resubmitted message', (tester) async {
    final fakeRepo = _FakeProfileRepository(
      _profile(status: 'rejected'),
      editProfileReturnStatus: 'pending_call',
    );
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: EditProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Age'), '33');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('resubmitted for review'), findsOneWidget);
  });
}
