import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/data/auth_repository.dart';
import 'package:nursenow_app/features/auth/data/auth_result.dart';
import 'package:nursenow_app/features/auth/screens/login_screen.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/data/individual_model.dart';

class _FakeAuthRepository extends AuthRepository {
  final ApiException? loginCodeError;
  bool loginCodeCalled = false;
  String? capturedPhone;
  String? capturedCode;
  String? capturedOtpPurpose;
  String? capturedPhoneVerificationToken;
  String verifyOtpReturnValue = 'verified-token';
  bool throwOnSendOtp = false;
  bool throwOnVerifyOtp = false;
  bool loginOtpCalled = false;

  _FakeAuthRepository({this.loginCodeError}) : super(Dio());

  @override
  Future<AuthResult> loginCode(String phone, String code) async {
    loginCodeCalled = true;
    capturedPhone = phone;
    capturedCode = code;
    if (loginCodeError != null) throw loginCodeError!;
    return const AuthResult(userId: 'u1', accessToken: 'access', refreshToken: 'refresh');
  }

  @override
  Future<void> sendOtp({required String phone, required String purpose}) async {
    capturedPhone = phone;
    capturedOtpPurpose = purpose;
    if (throwOnSendOtp) {
      throw const ApiException(code: 'GEN_004', message: 'Please wait before requesting another code');
    }
  }

  @override
  Future<String> verifyOtp({required String phone, required String otp, required String purpose}) async {
    capturedOtpPurpose = purpose;
    if (throwOnVerifyOtp) {
      throw const ApiException(code: 'AUTH_012', message: 'Invalid or expired OTP');
    }
    return verifyOtpReturnValue;
  }

  @override
  Future<AuthResult> loginOtp(String phone, String phoneVerificationToken) async {
    loginOtpCalled = true;
    capturedPhone = phone;
    capturedPhoneVerificationToken = phoneVerificationToken;
    return const AuthResult(userId: 'u1', accessToken: 'access', refreshToken: 'refresh');
  }
}

class _FakeIndividualRepository extends IndividualRepository {
  _FakeIndividualRepository() : super(Dio());

  @override
  Future<IndividualModel> getMe() async => const IndividualModel(
        userId: 'u1',
        fullName: 'Test Individual',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );
}

Future<void> _pumpLogin(WidgetTester tester, {required _FakeAuthRepository authRepo, bool otpMode = false}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
        individualRepositoryProvider.overrideWithValue(_FakeIndividualRepository()),
        otpModeProvider.overrideWith((ref) => otpMode),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
        routes: {'/home': (_) => const Scaffold(body: Text('home'))},
      ),
    ),
  );
}

void main() {
  testWidgets('shows phone and code fields', (tester) async {
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

  group('OTP mode', () {
    testWidgets('shows phone + Send OTP, no PIN field', (tester) async {
      await _pumpLogin(tester, authRepo: _FakeAuthRepository(), otpMode: true);

      expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
      expect(find.widgetWithText(TextField, '4-digit code'), findsNothing);
      expect(find.text('Send OTP'), findsOneWidget);
    });

    testWidgets('tapping Send OTP calls sendOtp with purpose login and reveals the OTP field', (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpLogin(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      expect(authRepo.capturedPhone, '+919876543210');
      expect(authRepo.capturedOtpPurpose, OtpPurpose.login);
      expect(find.widgetWithText(TextField, '6-digit OTP'), findsOneWidget);
      expect(find.text('Verify & Login'), findsOneWidget);
    });

    testWidgets('verifying the OTP calls verifyOtp then loginOtp and logs in', (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpLogin(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '6-digit OTP'), '123456');
      await tester.tap(find.text('Verify & Login'));
      await tester.pumpAndSettle();

      expect(authRepo.loginOtpCalled, isTrue);
      expect(authRepo.capturedPhoneVerificationToken, 'verified-token');
    });

    testWidgets('shows the server error when sendOtp fails', (tester) async {
      final authRepo = _FakeAuthRepository()..throwOnSendOtp = true;
      await _pumpLogin(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      expect(find.text('Please wait before requesting another code'), findsOneWidget);
    });

    testWidgets('shows the server error when verifyOtp fails, without calling loginOtp', (tester) async {
      final authRepo = _FakeAuthRepository()..throwOnVerifyOtp = true;
      await _pumpLogin(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6-digit OTP'), '000000');
      await tester.tap(find.text('Verify & Login'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or expired OTP'), findsOneWidget);
      expect(authRepo.loginOtpCalled, isFalse);
    });

    testWidgets('"Change phone number" resets back to the phone-only step', (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpLogin(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '6-digit OTP'), findsOneWidget);

      await tester.tap(find.text('Change phone number'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '6-digit OTP'), findsNothing);
      expect(find.text('Send OTP'), findsOneWidget);
    });
  });
}
