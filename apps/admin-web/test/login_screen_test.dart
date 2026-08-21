import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/data/auth_repository.dart';
import 'package:admin_web/features/auth/screens/login_screen.dart';

class _FakeAuthRepository extends AuthRepository {
  final ApiException? error;
  bool loginCalled = false;
  String? capturedEmail;

  _FakeAuthRepository({this.error}) : super(Dio());

  @override
  Future<AdminLoginResult> loginEmail(String email, String password) async {
    loginCalled = true;
    capturedEmail = email;
    if (error != null) throw error!;
    return const AdminLoginResult(
        userId: 'admin-1', accessToken: 'access', refreshToken: 'refresh');
  }
}

Future<void> _pumpLogin(WidgetTester tester,
    {required _FakeAuthRepository authRepo}) async {
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
  testWidgets('submits the trimmed email and password to the repository',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), '  admin@vitacasahealth.in  ');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(authRepo.loginCalled, isTrue);
    expect(authRepo.capturedEmail, 'admin@vitacasahealth.in');
  });

  testWidgets('shows the server error message on invalid credentials',
      (tester) async {
    final authRepo = _FakeAuthRepository(
      error: const ApiException(
          code: 'AUTH_003', message: 'Invalid email or password'),
    );
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'admin@vitacasahealth.in');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'wrongpass');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
  });

  testWidgets('shows the deactivated-account error distinctly', (tester) async {
    final authRepo = _FakeAuthRepository(
      error: const ApiException(
          code: 'AUTH_004', message: 'Account is deactivated'),
    );
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'admin@vitacasahealth.in');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Account is deactivated'), findsOneWidget);
  });
}
