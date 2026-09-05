import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/caregiver_messages/caregiver_messages_repository.dart';
import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/profile/screens/profile_view_screen.dart';

CaregiverProfileModel _profile({String status = 'pending_call', int age = 30, List<String>? languages, String? qualification}) {
  return CaregiverProfileModel.fromJson({
    'user_id': 'u1',
    'profile_id': 'p1',
    'caregiver_number': 500,
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'gender': 'male',
    'age': age,
    'languages': languages ?? ['hindi'],
    'highest_qualification': qualification,
    'religion': 'hindu',
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
  bool editProfileCalled = false;
  Map<String, dynamic> captured = {};
  String editProfileReturnStatus;
  bool updateCodeCalled = false;
  String? updatedCode;
  final ApiException? editProfileError;
  final ApiException? updateCodeError;

  _FakeProfileRepository(
    this.profile, {
    this.editProfileReturnStatus = 'available',
    this.editProfileError,
    this.updateCodeError,
  }) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<String> editProfile({int? age, List<String>? languages, String? highestQualification}) async {
    if (editProfileError != null) throw editProfileError!;
    editProfileCalled = true;
    captured = {'age': age, 'languages': languages, 'highestQualification': highestQualification};
    return editProfileReturnStatus;
  }

  @override
  Future<void> updateCode(String code) async {
    if (updateCodeError != null) throw updateCodeError!;
    updateCodeCalled = true;
    updatedCode = code;
  }
}

class _FakeJobsRepository extends JobsRepository {
  _FakeJobsRepository() : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async => const [];

  @override
  Future<List<JobModel>> getAssignedJobs() async => const [];
}

class _FakeCaregiverMessagesRepository extends CaregiverMessagesRepository {
  _FakeCaregiverMessagesRepository() : super(Dio());

  @override
  Future<List<CaregiverMessageModel>> get() async => const [];
}

Future<void> _pumpTall(WidgetTester tester, _FakeProfileRepository fakeRepo) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(fakeRepo),
        jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository()),
        localStorageProvider.overrideWithValue(localStorage),
        caregiverMessagesRepositoryProvider.overrideWithValue(_FakeCaregiverMessagesRepository()),
      ],
      child: const MaterialApp(home: ProfileViewScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapEditPencil(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Edit $label'));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows basic profile fields read-only, with no pencil icon on Full Name/Phone/Gender/Religion',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(tester, fakeRepo);

    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('NUR-500'), findsOneWidget);
    // Explanatory text about changing the phone number lives right next to
    // where it's actually shown (Basic Info), not duplicated elsewhere.
    expect(find.textContaining('tap the Help button above to chat with us on WhatsApp'), findsOneWidget);
    expect(find.byTooltip('Edit Full Name'), findsNothing);
    expect(find.byTooltip('Edit Phone'), findsNothing);
    expect(find.byTooltip('Edit Gender'), findsNothing);
    expect(find.byTooltip('Edit Religion'), findsNothing);
  });

  testWidgets('Age, Languages, Qualification, and Login PIN each have their own pencil icon — no separate '
      'Edit Profile screen', (tester) async {
    for (final status in ['pending_call', 'available', 'unavailable', 'assigned', 'rejected']) {
      final fakeRepo = _FakeProfileRepository(_profile(status: status));
      await _pumpTall(tester, fakeRepo);

      expect(find.byTooltip('Edit Age'), findsOneWidget, reason: 'status: $status');
      expect(find.byTooltip('Edit Languages'), findsOneWidget, reason: 'status: $status');
      expect(find.byTooltip('Edit Qualification'), findsOneWidget, reason: 'status: $status');
      expect(find.byTooltip('Edit Login PIN'), findsOneWidget, reason: 'status: $status');
      expect(find.widgetWithText(TextButton, 'Edit'), findsNothing, reason: 'status: $status');
    }
  });

  testWidgets('rejected status shows the rejection message', (tester) async {
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
    await _pumpTall(tester, fakeRepo);

    expect(find.textContaining('Aadhaar unreadable'), findsOneWidget);
  });

  testWidgets('does not show the job poster\'s contact info (phone/call/WhatsApp) — that now lives only on MyJobs',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(status: 'assigned'));
    await _pumpTall(tester, fakeRepo);

    expect(find.text('Posted by'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsNothing);
  });

  testWidgets('does not show an Available for Jobs button — self-service mark-available was removed entirely',
      (tester) async {
    for (final status in ['pending_call', 'available', 'unavailable', 'assigned', 'rejected']) {
      final fakeRepo = _FakeProfileRepository(_profile(status: status));
      await _pumpTall(tester, fakeRepo);
      expect(find.widgetWithText(ElevatedButton, 'Available for Jobs'), findsNothing, reason: 'status: $status');
    }
  });

  group('Age — inline pencil edit', () {
    testWidgets('tapping the pencil reveals a numeric field prefilled with the current age', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(age: 30));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Age'));
      expect(field.controller?.text, '30');
      expect(field.keyboardType, TextInputType.number);
    });

    testWidgets('saving a valid age calls editProfile with only age set, and closes back to the pencil',
        (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(age: 30));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '35');
      await _tapSave(tester);

      expect(fakeRepo.editProfileCalled, isTrue);
      expect(fakeRepo.captured['age'], 35);
      expect(fakeRepo.captured['languages'], isNull);
      expect(fakeRepo.captured['highestQualification'], isNull);
      expect(find.widgetWithText(TextField, 'Age'), findsNothing);
      expect(find.text('Saved. Your admin will see this change flagged for review.'), findsOneWidget);
    });

    testWidgets('rejects an out-of-range age without calling the repository', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(age: 30));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '5');
      await _tapSave(tester);

      expect(fakeRepo.editProfileCalled, isFalse);
      expect(find.text('Age must be between ${Validation.ageMin} and ${Validation.ageMax}'), findsOneWidget);
    });

    testWidgets('shows "resubmitted for review" instead when the account was rejected', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(status: 'rejected', age: 30), editProfileReturnStatus: 'pending_call');
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '35');
      await _tapSave(tester);

      expect(find.text('Saved. Your profile has been resubmitted for review.'), findsOneWidget);
    });

    testWidgets('shows a server error message when the save fails, and stays in edit mode', (tester) async {
      final fakeRepo = _FakeProfileRepository(
        _profile(age: 30),
        editProfileError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
      );
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '35');
      await _tapSave(tester);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Age'), findsOneWidget);
    });

    testWidgets('tapping Cancel discards the change', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(age: 30));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Age');
      await tester.enterText(find.widgetWithText(TextField, 'Age'), '99');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(fakeRepo.editProfileCalled, isFalse);
      expect(find.text('30'), findsOneWidget);
      expect(find.byTooltip('Edit Age'), findsOneWidget);
    });
  });

  group('Languages — inline pencil edit', () {
    testWidgets('saving a new selection calls editProfile with only languages set', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(languages: ['hindi']));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Languages');
      await tester.tap(find.text(Language.displayNames[Language.english]!));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(fakeRepo.editProfileCalled, isTrue);
      expect(fakeRepo.captured['languages'], containsAll(['hindi', 'english']));
      expect(fakeRepo.captured['age'], isNull);
      expect(fakeRepo.captured['highestQualification'], isNull);
    });

    testWidgets('rejects deselecting every language without calling the repository', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(languages: ['hindi']));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Languages');
      await tester.tap(find.text(Language.displayNames[Language.hindi]!));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(fakeRepo.editProfileCalled, isFalse);
      expect(find.text('Select at least one language'), findsOneWidget);
    });
  });

  group('Qualification — inline pencil edit', () {
    testWidgets('saving a selection calls editProfile with only highestQualification set', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile(qualification: Qualification.all.first));
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Qualification');
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Qualification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Qualification.displayNames[Qualification.all[1]]!).last);
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(fakeRepo.editProfileCalled, isTrue);
      expect(fakeRepo.captured['highestQualification'], Qualification.all[1]);
      expect(fakeRepo.captured['age'], isNull);
      expect(fakeRepo.captured['languages'], isNull);
    });
  });

  group('Login PIN — inline pencil edit', () {
    testWidgets('shows a masked placeholder, with an empty input revealed on tapping the pencil', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile());
      await _pumpTall(tester, fakeRepo);

      expect(find.text('••••'), findsOneWidget);
      await _tapEditPencil(tester, 'Login PIN');

      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'New 4-Digit PIN'));
      expect(field.controller?.text, isEmpty);
      expect(field.maxLength, Validation.codeLength);
    });

    testWidgets('saving a valid 4-digit code calls updateCode and returns to the masked display', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile());
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Login PIN');
      await tester.enterText(find.widgetWithText(TextField, 'New 4-Digit PIN'), '4321');
      await _tapSave(tester);

      expect(fakeRepo.updateCodeCalled, isTrue);
      expect(fakeRepo.updatedCode, '4321');
      expect(find.text('••••'), findsOneWidget);
      expect(find.text('Login code updated.'), findsOneWidget);
    });

    testWidgets('rejects a code that is not exactly 4 digits without calling the repository', (tester) async {
      final fakeRepo = _FakeProfileRepository(_profile());
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Login PIN');
      await tester.enterText(find.widgetWithText(TextField, 'New 4-Digit PIN'), '12');
      await _tapSave(tester);

      expect(fakeRepo.updateCodeCalled, isFalse);
      expect(find.text('Code must be exactly 4 digits'), findsOneWidget);
    });

    testWidgets('shows a server error message when the save fails', (tester) async {
      final fakeRepo = _FakeProfileRepository(
        _profile(),
        updateCodeError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'),
      );
      await _pumpTall(tester, fakeRepo);

      await _tapEditPencil(tester, 'Login PIN');
      await tester.enterText(find.widgetWithText(TextField, 'New 4-Digit PIN'), '4321');
      await _tapSave(tester);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'New 4-Digit PIN'), findsOneWidget);
    });
  });

  group('Documents', () {
    testWidgets('shows Upload for missing documents and Replace for already-uploaded ones', (tester) async {
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
        'verification_status': 'pending_call',
        'created_at': '2026-08-01T10:00:00Z',
        'selfie_photo_url': 'https://signed/selfie',
      });
      final fakeRepo = _FakeProfileRepository(profile);
      await _pumpTall(tester, fakeRepo);

      expect(find.text('Selfie (mandatory)'), findsOneWidget);
      expect(find.text('Aadhaar Card (mandatory)'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Replace'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Upload'), findsWidgets);
    });
  });
}
