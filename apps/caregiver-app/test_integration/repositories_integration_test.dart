import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caregiver_app/core/network/api_client.dart';
import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/auth/data/auth_repository.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';

/// Exercises the exact repository code the screens call, against a real
/// locally-running instance of apps/api (http://localhost:3000/v1) and the
/// real Supabase project. Deliberately kept out of test/ so plain
/// `flutter test` / `melos run test` stay hermetic (no server dependency).
///
/// To run: start the API server, then from apps/caregiver-app:
///   cd ../api && node dist/main.js &
///   cd ../caregiver-app && flutter test test_integration/repositories_integration_test.dart
/// Uses the +91700002xxxx test phone range, distinct from apps/api's own
/// e2e suites (+91700000xxxx / +91700001xxxx). Clean up test data afterward —
/// see the DB/storage cleanup commands used in apps/api's own e2e specs.
void main() {
  late LocalStorage localStorage;
  late AuthRepository authRepo;
  late ProfileRepository profileRepo;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    localStorage = await LocalStorage.create();
    final apiClient = ApiClient(localStorage);
    authRepo = AuthRepository(apiClient.dio);
    profileRepo = ProfileRepository(apiClient.dio);
  });

  String testPhone(String suffix) => '+91700002$suffix';

  test('register -> getProfile -> updateBasic -> upload selfie/qualification/aadhaar', () async {
    final result = await authRepo.register(
      phone: testPhone('0001'),
      fullName: 'Repo Test',
      gender: 'male',
      age: 29,
      languages: ['hindi'],
      code: '1234',
    );
    expect(result.verificationStatus, 'pending_call');
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);

    final profile = await profileRepo.getProfile();
    expect(profile.fullName, 'Repo Test');
    expect(profile.languages, ['hindi']);
    expect(profile.selfiePhotoUrl, isNull);
    expect(profile.hasRequiredDocuments, isFalse);

    await profileRepo.updateBasic(
      age: 30,
      languages: ['hindi', 'english'],
    );
    final updated = await profileRepo.getProfile();
    expect(updated.fullName, 'Repo Test'); // unchanged — caregivers can't self-edit their name
    expect(updated.languages, ['hindi', 'english']);
    expect(updated.verificationStatus, 'pending_call', reason: 'basic edits must not change status');

    final selfieBytes = Uint8List.fromList('fake selfie bytes'.codeUnits);
    final qualificationBytes = Uint8List.fromList('fake qualification'.codeUnits);
    final aadhaarBytes = Uint8List.fromList('fake aadhaar'.codeUnits);

    await profileRepo.uploadSelfie(selfieBytes, 'selfie.jpg');
    await profileRepo.uploadDocument(qualificationBytes, 'qualification.pdf', 'qualification');
    await profileRepo.uploadDocument(aadhaarBytes, 'aadhaar.pdf', 'aadhaar');

    final withDocs = await profileRepo.getProfile();
    expect(withDocs.hasRequiredDocuments, isTrue);
    expect(withDocs.selfiePhotoUrl, isNotNull);
  });

  test('submitAdvanced throws PROFILE_008 (as ApiException) while still pending_call', () async {
    final result = await authRepo.register(
      phone: testPhone('0002'),
      fullName: 'Repo Test Two',
      gender: 'female',
      age: 25,
      languages: ['tamil'],
      code: '1234',
    );
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);

    await expectLater(
      profileRepo.submitAdvanced(
        highestQualification: 'rn_above_2_years',
        religion: 'hindu',
        fatherName: 'Suresh Kumar',
        fatherPhone: '+919876500001',
        currentAddress: '123 MG Road',
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PROFILE_008')),
    );
  });

  test('register with a duplicate phone throws ApiException(AUTH_001)', () async {
    await authRepo.register(
      phone: testPhone('0003'),
      fullName: 'Repo Test Three',
      gender: 'male',
      age: 40,
      languages: ['hindi'],
      code: '1234',
    );

    await expectLater(
      authRepo.register(
        phone: testPhone('0003'),
        fullName: 'Repo Test Three Again',
        gender: 'male',
        age: 40,
        languages: ['hindi'],
        code: '1234',
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_001')),
    );
  });

  test('loginCode succeeds with the code set at registration', () async {
    await authRepo.register(
      phone: testPhone('0004'),
      fullName: 'Repo Test Four',
      gender: 'other',
      age: 35,
      languages: ['english'],
      code: '5678',
    );

    final login = await authRepo.loginCode(testPhone('0004'), '5678');
    expect(login.verificationStatus, 'pending_call');
    expect(login.advancedDetailsCompleted, isFalse);
  });

  test('loginCode with an unregistered phone throws ApiException(AUTH_002)', () async {
    await expectLater(
      authRepo.loginCode(testPhone('9999'), '1234'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_002')),
    );
  });
}
