import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/data/auth_repository.dart';
import 'package:nursenow_app/features/auth/data/auth_result.dart';
import 'package:nursenow_app/features/auth/screens/registration_screen.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/data/individual_model.dart';

class _FakeAuthRepository extends AuthRepository {
  final ApiException? registerError;
  bool registerCalled = false;
  String? capturedPhone;
  String? capturedFullName;
  String? capturedCode;

  _FakeAuthRepository({this.registerError}) : super(Dio());

  @override
  Future<AuthResult> register({required String phone, required String fullName, required String code}) async {
    registerCalled = true;
    capturedPhone = phone;
    capturedFullName = fullName;
    capturedCode = code;
    if (registerError != null) throw registerError!;
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

Future<void> _pumpRegistration(WidgetTester tester, {required _FakeAuthRepository authRepo}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
        individualRepositoryProvider.overrideWithValue(_FakeIndividualRepository()),
      ],
      child: MaterialApp(
        home: const RegistrationScreen(),
        routes: {'/home': (_) => const Scaffold(body: Text('home'))},
      ),
    ),
  );
}

void main() {
  testWidgets('blocks submission without an account type selected, without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha Patel');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    expect(find.text('Select an account type'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('blocks submission for Hospital/Rehab (not built yet), without calling register', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'City Hospital');
    await tester.tap(find.text('Hospital / Rehab'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    expect(find.text('Hospital/Rehab registration is coming soon.'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('registers an Individual account with phone, full name, and code', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha Patel');
    await tester.tap(find.text('Individual'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(authRepo.registerCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedFullName, 'Asha Patel');
    expect(authRepo.capturedCode, '1234');
  });

  testWidgets('shows the server error message for registration failures', (tester) async {
    final authRepo = _FakeAuthRepository(
      registerError: const ApiException(code: 'AUTH_001', message: 'Phone number is already registered'),
    );
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha Patel');
    await tester.tap(find.text('Individual'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.text('Phone number is already registered'), findsOneWidget);
  });
}
