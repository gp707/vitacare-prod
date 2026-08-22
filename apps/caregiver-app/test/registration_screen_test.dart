import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/auth/data/auth_repository.dart';
import 'package:caregiver_app/features/auth/data/auth_result.dart';
import 'package:caregiver_app/features/registration/screens/registration_screen.dart';

class _FakeAuthRepository extends AuthRepository {
  bool registerCalled = false;
  String? capturedCode;

  _FakeAuthRepository() : super(Dio());

  @override
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required String gender,
    required int age,
    required List<String> languages,
    required String code,
    required String religion,
    required String highestQualification,
    required bool termsAccepted,
    List<String>? preferredCities,
  }) async {
    registerCalled = true;
    capturedCode = code;
    return const AuthResult(
      userId: 'u1',
      profileId: 'p1',
      accessToken: 'access',
      refreshToken: 'refresh',
      verificationStatus: 'pending_call',
    );
  }
}

/// The registration form is long; without a tall surface, Flutter's Sliver
/// system never mounts the submit button (it's outside the viewport + cache
/// extent), so `find` can't see it even though it "exists" logically.
Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

Future<void> _pumpRegistration(
  WidgetTester tester,
  _FakeAuthRepository authRepo, {
  Future<bool> Function(Uri uri)? launcher,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await _pumpTall(
    tester,
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: MaterialApp(home: RegistrationScreen(launcher: launcher)),
    ),
  );
}

/// Fills name/phone/age/language/code — the fields that come before
/// Religion in validation order — so later-field tests can start from there.
Future<void> _fillUpToCode(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Full Name (Mandatory)'), 'Ramesh Kumar');
  await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
  await tester.enterText(find.widgetWithText(TextField, 'Age (Mandatory)'), '30');
  await tester.tap(find.text('Hindi'));
  await tester.enterText(find.widgetWithText(TextField, '4-Digit Login Code (Mandatory)'), '1234');
  await tester.pump();
}

Future<void> _selectReligion(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text(Religion.displayNames[Religion.hindu]!).last);
  await tester.pumpAndSettle();
}

Future<void> _selectQualification(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text(Qualification.displayNames[Qualification.all.first]!).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocks submission without a 4-digit code, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name (Mandatory)'), 'Ramesh Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Age (Mandatory)'), '30');
    await tester.tap(find.text('Hindi'));
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text("Set a 4-digit code — you'll use it with your phone to log in"), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission without religion selected, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);
    await _fillUpToCode(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Select your religion'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission without a qualification selected, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);
    await _fillUpToCode(tester);
    await _selectReligion(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Select your highest qualification'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission without a selfie, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);
    await _fillUpToCode(tester);
    await _selectReligion(tester);
    await _selectQualification(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Take a selfie to continue'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission with an invalid name before checking anything else', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name (Mandatory)'), 'Ramesh123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Enter a valid full name (letters and spaces only)'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('tapping Register with everything empty flags every mandatory field red at once, not just the first',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Every mandatory field's error is shown simultaneously — not just the
    // first invalid one found.
    expect(find.text('Enter a valid full name (letters and spaces only)'), findsOneWidget);
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(find.text("Set a 4-digit code — you'll use it with your phone to log in"), findsOneWidget);
    expect(find.text('Age must be between ${Validation.ageMin} and ${Validation.ageMax}'), findsOneWidget);
    expect(find.text('Select at least one language'), findsOneWidget);
    expect(find.text('Select your religion'), findsOneWidget);
    expect(find.text('Select your highest qualification'), findsOneWidget);
    expect(find.text('Take a selfie to continue'), findsOneWidget);
    expect(find.text('Upload your Aadhaar card to continue'), findsOneWidget);
    expect(find.text('You must accept the Terms & Conditions to continue'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('fields do not show red until Register has been tapped once', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    expect(find.text('Select at least one language'), findsNothing);
    expect(find.text('Take a selfie to continue'), findsNothing);
  });

  testWidgets('shows a Terms & Conditions checkbox with a tappable link to the terms document', (tester) async {
    final authRepo = _FakeAuthRepository();
    Uri? openedUri;
    await _pumpRegistration(
      tester,
      authRepo,
      launcher: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.textContaining('Terms & Conditions', findRichText: true), findsOneWidget);

    // Tap the exact substring's own rendered bounds — tapping the whole
    // RichText's center is unreliable once the sentence wraps onto more
    // than one line (the center point may land on a different span).
    await tester.tapOnText(find.textRange.ofSubstring('Terms & Conditions'));
    await tester.pumpAndSettle();

    expect(
      openedUri,
      Uri.parse('https://docs.google.com/document/d/17BQ8hGoZ-U6Tqio-5pNsTZaDtQTlnl0XjJtmET0sG_Q/edit?tab=t.0'),
    );
  });
}
