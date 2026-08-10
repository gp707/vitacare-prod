import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }) async {
    registerCalled = true;
    capturedCode = code;
    return const AuthResult(
      userId: 'u1',
      profileId: 'p1',
      accessToken: 'access',
      refreshToken: 'refresh',
      verificationStatus: 'pending_call',
      advancedDetailsCompleted: false,
    );
  }
}

/// The registration form is long; without a tall surface, Flutter's Sliver
/// system never mounts the submit button (it's outside the viewport + cache
/// extent), so `find` can't see it even though it "exists" logically.
Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

Future<void> _pumpRegistration(WidgetTester tester, _FakeAuthRepository authRepo) async {
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
      child: const MaterialApp(home: RegistrationScreen()),
    ),
  );
}

void main() {
  testWidgets('blocks submission without a 4-digit code, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Ramesh Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Age'), '30');
    await tester.tap(find.text('Hindi'));
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text("Set a 4-digit code — you'll use it with your phone to log in"), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission without a selfie, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Ramesh Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Age'), '30');
    await tester.tap(find.text('Hindi'));
    await tester.enterText(find.widgetWithText(TextField, '4-Digit Login Code'), '1234');
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Take a selfie to continue'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission with an invalid name before checking anything else', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name'), 'Ramesh123');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('Enter a valid full name (letters and spaces only)'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('displays the informational salary ranges', (tester) async {
    await _pumpRegistration(tester, _FakeAuthRepository());

    expect(find.textContaining('Companion Care'), findsOneWidget);
    expect(find.textContaining('₹25000'), findsOneWidget);
  });
}
