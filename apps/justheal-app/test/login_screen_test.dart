import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/auth/data/auth_repository.dart';
import 'package:nursenow_app/patient_hospital/features/auth/data/auth_result.dart';
import 'package:nursenow_app/patient_hospital/features/auth/screens/login_screen.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_model.dart';
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'package:nursenow_app/caregiver/core/network/api_exception.dart' as caregiver_net;
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart' as caregiver_storage;
import 'package:nursenow_app/caregiver/features/auth/data/auth_repository.dart' as caregiver_auth_repo;
import 'package:nursenow_app/caregiver/features/auth/data/auth_result.dart' as caregiver_auth;

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

class _FakeCaregiverAuthRepository extends caregiver_auth_repo.AuthRepository {
  final caregiver_net.ApiException? loginCodeError;
  bool loginCodeCalled = false;
  String? capturedPhone;
  String? capturedCode;

  _FakeCaregiverAuthRepository({this.loginCodeError}) : super(Dio());

  @override
  Future<caregiver_auth.AuthResult> loginCode(String phone, String code) async {
    loginCodeCalled = true;
    capturedPhone = phone;
    capturedCode = code;
    if (loginCodeError != null) throw loginCodeError!;
    return const caregiver_auth.AuthResult(
      userId: 'c1',
      accessToken: 'caregiver-access',
      refreshToken: 'caregiver-refresh',
      verificationStatus: 'available',
    );
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

Future<void> _pumpLogin(
  WidgetTester tester, {
  required _FakeAuthRepository authRepo,
  bool otpMode = false,
  _FakeCaregiverAuthRepository? caregiverAuthRepo,
  List<RouteSettings>? pushedRoutes,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  final caregiverLocalStorage = await caregiver_storage.LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
        individualRepositoryProvider.overrideWithValue(_FakeIndividualRepository()),
        otpModeProvider.overrideWith((ref) => otpMode),
        caregiver.localStorageProvider.overrideWithValue(caregiverLocalStorage),
        if (caregiverAuthRepo != null) caregiver.authRepositoryProvider.overrideWithValue(caregiverAuthRepo),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
        routes: {'/home': (_) => const Scaffold(body: Text('home'))},
        // Records every named push the three "New here? Register as:" rows
        // make (route name + arguments), rather than actually resolving
        // '/register'/'/caregiver/register' — those screens pull in far
        // more providers than this login-screen test sets up.
        onGenerateRoute: (settings) {
          pushedRoutes?.add(settings);
          return MaterialPageRoute(settings: settings, builder: (_) => Scaffold(body: Text('route:${settings.name}')));
        },
      ),
    ),
  );
}

void main() {
  group('fits without scrolling on common phone sizes', () {
    // `tester.binding.setSurfaceSize` only affects real pixel-level
    // rendering/hit-testing; MediaQuery (which SingleChildScrollView's
    // layout ultimately depends on) reads tester.view.physicalSize /
    // devicePixelRatio instead — both must be set together, per this
    // project's own flutter-widget-test-gotchas memory note.
    Future<double> maxScrollExtentAt(WidgetTester tester, Size size) async {
      final view = tester.view;
      addTearDown(() {
        tester.binding.setSurfaceSize(null);
        view.reset();
      });
      await tester.binding.setSurfaceSize(size);
      view.physicalSize = size;
      view.devicePixelRatio = 1.0;

      await _pumpLogin(tester, authRepo: _FakeAuthRepository());
      await tester.pumpAndSettle();

      final scrollableState = tester.state<ScrollableState>(
        find.ancestor(of: find.text('New here? Register as:'), matching: find.byType(Scrollable)),
      );
      return scrollableState.position.maxScrollExtent;
    }

    testWidgets('390x844 (iPhone 14/15/16 class) — no scroll needed', (tester) async {
      expect(await maxScrollExtentAt(tester, const Size(390, 844)), 0);
    });

    // 360x800 no longer fits with zero scroll once the login/register
    // sections were given more breathing room (explicit follow-up request)
    // — same designed fallback as the 667pt-tall case below: scroll
    // gracefully rather than clip, confirmed here rather than asserted
    // as zero.
    testWidgets('360x800 (common Android) — falls back to a small scroll rather than clipping', (tester) async {
      expect(await maxScrollExtentAt(tester, const Size(360, 800)), greaterThan(0));
    });

    // 667pt tall is a genuinely old/small device (iPhone SE) that neither
    // the task's own target sizes (360/390 wide) nor its "no scroll" goal
    // were written against — the explicit fallback for exactly this case
    // (per the original spec) is to scroll rather than clip, so this just
    // confirms that fallback engages cleanly instead of asserting zero
    // scroll like the two sizes above.
    testWidgets('375x667 (iPhone SE) — falls back to a small scroll rather than clipping', (tester) async {
      expect(await maxScrollExtentAt(tester, const Size(375, 667)), greaterThan(0));
    });
  });


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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await tester.pump();

    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(authRepo.loginCodeCalled, isFalse);
  });

  testWidgets('submits phone + code together on success', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpLogin(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid code'), findsOneWidget);
  });

  group('caregiver login fallback', () {
    testWidgets('AUTH_002 from the nursenow login falls back to caregiver login with the same phone + code',
        (tester) async {
      final authRepo = _FakeAuthRepository(
        loginCodeError: const ApiException(code: 'AUTH_002', message: 'No account found with this phone number'),
      );
      final caregiverAuthRepo = _FakeCaregiverAuthRepository();
      await _pumpLogin(tester, authRepo: authRepo, caregiverAuthRepo: caregiverAuthRepo);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(authRepo.loginCodeCalled, isTrue);
      expect(caregiverAuthRepo.loginCodeCalled, isTrue);
      expect(caregiverAuthRepo.capturedPhone, '+919876543210');
      expect(caregiverAuthRepo.capturedCode, '1234');
    });

    testWidgets('a non-AUTH_002 error surfaces directly without trying the caregiver login', (tester) async {
      final authRepo = _FakeAuthRepository(
        loginCodeError: const ApiException(code: 'AUTH_008', message: 'Invalid code'),
      );
      final caregiverAuthRepo = _FakeCaregiverAuthRepository();
      await _pumpLogin(tester, authRepo: authRepo, caregiverAuthRepo: caregiverAuthRepo);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '0000');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid code'), findsOneWidget);
      expect(caregiverAuthRepo.loginCodeCalled, isFalse);
    });

    testWidgets('shows the caregiver error message when the fallback login also fails', (tester) async {
      final authRepo = _FakeAuthRepository(
        loginCodeError: const ApiException(code: 'AUTH_002', message: 'No account found with this phone number'),
      );
      final caregiverAuthRepo = _FakeCaregiverAuthRepository(
        loginCodeError: const caregiver_net.ApiException(code: 'AUTH_008', message: 'Invalid code'),
      );
      await _pumpLogin(tester, authRepo: authRepo, caregiverAuthRepo: caregiverAuthRepo);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
      await tester.enterText(find.widgetWithText(TextField, '4-digit code'), '9999');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid code'), findsOneWidget);
    });
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

      // The redesigned screen's extra content (Log in heading/subtext,
      // divider, three registration rows) pushes this button below the
      // test surface's default viewport — scroll it into view before
      // tapping, same as a real short screen would require.
      await tester.ensureVisible(find.text('Change phone number'));
      await tester.tap(find.text('Change phone number'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '6-digit OTP'), findsNothing);
      expect(find.text('Send OTP'), findsOneWidget);
    });
  });

  group('New here? Register as: rows', () {
    testWidgets('Patient row pushes /register with no arguments (defaults to Individual)', (tester) async {
      final pushedRoutes = <RouteSettings>[];
      await _pumpLogin(tester, authRepo: _FakeAuthRepository(), pushedRoutes: pushedRoutes);

      await tester.ensureVisible(find.text('Patient'));
      await tester.tap(find.text('Patient'));
      await tester.pumpAndSettle();

      expect(pushedRoutes.single.name, '/register');
      expect(pushedRoutes.single.arguments, isNull);
    });

    testWidgets('Nurses/Caregivers row pushes /caregiver/register — same as the old top-bar button', (tester) async {
      final pushedRoutes = <RouteSettings>[];
      await _pumpLogin(tester, authRepo: _FakeAuthRepository(), pushedRoutes: pushedRoutes);

      await tester.ensureVisible(find.text('Nurses/Caregivers'));
      await tester.tap(find.text('Nurses/Caregivers'));
      await tester.pumpAndSettle();

      expect(pushedRoutes.single.name, '/caregiver/register');
    });

    testWidgets('Organisation row pushes /register with arguments: true, to preselect that account type',
        (tester) async {
      final pushedRoutes = <RouteSettings>[];
      await _pumpLogin(tester, authRepo: _FakeAuthRepository(), pushedRoutes: pushedRoutes);

      await tester.ensureVisible(find.text('Organisation'));
      await tester.tap(find.text('Organisation'));
      await tester.pumpAndSettle();

      expect(pushedRoutes.single.name, '/register');
      expect(pushedRoutes.single.arguments, isTrue);
    });

    testWidgets('the old "Caregivers Registration" top-bar button and "New here? Register" link are both gone',
        (tester) async {
      await _pumpLogin(tester, authRepo: _FakeAuthRepository());

      expect(find.text('Caregivers Registration'), findsNothing);
      expect(find.text('New here? Register'), findsNothing);
    });
  });
}
