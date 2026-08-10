import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/auth/data/auth_repository.dart';
import 'package:caregiver_app/features/auth/data/auth_result.dart';
import 'package:caregiver_app/features/auth/screens/login_screen.dart';

class _FakeAuthRepository extends AuthRepository {
  final ApiException? loginCodeError;
  bool loginCodeCalled = false;
  String? capturedPhone;
  String? capturedCode;

  _FakeAuthRepository({this.loginCodeError}) : super(Dio());

  @override
  Future<AuthResult> loginCode(String phone, String code) async {
    loginCodeCalled = true;
    capturedPhone = phone;
    capturedCode = code;
    if (loginCodeError != null) throw loginCodeError!;
    return const AuthResult(
      userId: 'u1',
      accessToken: 'access',
      refreshToken: 'refresh',
      verificationStatus: 'available',
      advancedDetailsCompleted: true,
    );
  }
}

Future<void> _pumpLogin(WidgetTester tester, {required _FakeAuthRepository authRepo}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
}

void main() {
  testWidgets('always shows both phone and code fields (no phone-only login anymore)', (tester) async {
    await _pumpLogin(tester, authRepo: _FakeAuthRepository());

    expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
    expect(find.widgetWithText(TextField, '4-digit code'), findsOneWidget);
  });

  testWidgets('shows a validation error for a malformed phone without calling the API', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '123');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(authRepo.loginCodeCalled, isFalse);
  });

  testWidgets('shows a validation error for a missing code without calling the API', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Enter the 4-digit code'), findsOneWidget);
    expect(authRepo.loginCodeCalled, isFalse);
  });

  testWidgets('submits phone + code together on success', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(authRepo.loginCodeCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedCode, '1234');
  });

  testWidgets('shows the server error message for login failures', (tester) async {
    final authRepo = _FakeAuthRepository(
      loginCodeError: const ApiException(code: 'AUTH_008', message: 'Invalid code'),
    );
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '0000');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid code'), findsOneWidget);
  });
}
