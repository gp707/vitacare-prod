import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/advanced_details_screen.dart';

CaregiverProfileModel _profile({bool aadhaarUploaded = false, bool qualificationUploaded = false}) {
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
    'verification_status': 'call_verified',
    'advanced_details_completed': false,
    'created_at': '2026-08-01T10:00:00Z',
    'selfie_photo_url': 'https://signed/selfie',
    'qualification_document_url': qualificationUploaded ? 'https://signed/qual' : null,
    'aadhaar_document_url': aadhaarUploaded ? 'https://signed/aadhaar' : null,
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  bool submitAdvancedCalled = false;

  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<String> submitAdvanced({
    required String highestQualification,
  }) async {
    submitAdvancedCalled = true;
    return 'pending_verification';
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(Qualification.displayNames[Qualification.all.first]!).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('I accept the Terms & Conditions (mandatory)'));
  await tester.pump();
}

void main() {
  testWidgets('documents section shows Aadhaar as required and qualification as optional', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aadhaar Card (mandatory)'), findsOneWidget);
    expect(find.text('Qualification Document (optional)'), findsOneWidget);
  });

  testWidgets('Submit stays disabled while aadhaar is missing, even with everything else filled', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await _fillRequiredFields(tester);

    final submitButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitButton.onPressed, isNull);
    expect(fakeRepo.submitAdvancedCalled, isFalse);
  });

  testWidgets('Submit becomes enabled once aadhaar is uploaded, even without the qualification document',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(aadhaarUploaded: true, qualificationUploaded: false));

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await _fillRequiredFields(tester);

    final submitButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitButton.onPressed, isNotNull);
    expect(fakeRepo.submitAdvancedCalled, isFalse);
  });

  testWidgets('Submit stays disabled until Highest Qualification is selected', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(aadhaarUploaded: true));

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I accept the Terms & Conditions (mandatory)'));
    await tester.pump();

    final submitButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('shows Replace for aadhaar once uploaded, Upload for qualification while still unset', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(aadhaarUploaded: true, qualificationUploaded: false));

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Upload'), findsWidgets);
  });

  testWidgets('rejected resubmission: prefills the qualification dropdown, Submit already enabled', (tester) async {
    final rejectedProfile = CaregiverProfileModel.fromJson({
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
      'advanced_details_completed': true,
      'created_at': '2026-08-01T10:00:00Z',
      'selfie_photo_url': 'https://signed/selfie',
      'qualification_document_url': 'https://signed/qual',
      'aadhaar_document_url': 'https://signed/aadhaar',
      'highest_qualification': 'rn_above_2_years',
      'religion': 'hindu',
    });
    final fakeRepo = _FakeProfileRepository(rejectedProfile);

    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: AdvancedDetailsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Qualification.displayNames[Qualification.rnAbove2Years]!),
        findsOneWidget); // qualification dropdown, prefilled
    expect(find.text('Replace'), findsNWidgets(2)); // aadhaar + qualification already uploaded

    final submitButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitButton.onPressed, isNotNull);
  });
}
