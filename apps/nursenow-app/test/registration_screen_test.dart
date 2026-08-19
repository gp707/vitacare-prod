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
  bool registerOrganisationCalled = false;
  String? capturedPhone;
  String? capturedFullName;
  String? capturedCode;
  String? capturedOrganisationName;
  String? capturedContactPersonName;
  String? capturedOrganisationType;
  String? capturedCity;
  String? capturedArea;

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

  @override
  Future<AuthResult> registerOrganisation({
    required String phone,
    required String code,
    required String organisationName,
    required String contactPersonName,
    required String organisationType,
    required String city,
    required String area,
  }) async {
    registerOrganisationCalled = true;
    capturedPhone = phone;
    capturedCode = code;
    capturedOrganisationName = organisationName;
    capturedContactPersonName = contactPersonName;
    capturedOrganisationType = organisationType;
    capturedCity = city;
    capturedArea = area;
    if (registerError != null) throw registerError!;
    return const AuthResult(userId: 'org-1', accessToken: 'access', refreshToken: 'refresh');
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
  // The organisation fields push the form well past the default 800x600
  // viewport + cache extent — a plain ListView's sliver won't mount
  // widgets that far below the fold without a taller surface.
  await tester.binding.setSurfaceSize(const Size(400, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
  testWidgets(
      'Register is always tappable; tapping it with every mandatory field empty highlights all of them in red and does not submit',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(find.text('Enter a 4-digit PIN'), findsOneWidget);
    expect(find.text('Enter a name (letters and spaces only)'), findsOneWidget);
    expect(find.text('Select an account type'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('tapping Register with only full name missing does not submit and moves focus into the name field',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    // Full name deliberately left blank.
    await tester.tap(find.text('Individual'));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    expect(find.text('Enter a name (letters and spaces only)'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
    final fullNameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Full name (Mandatory)'));
    expect(fullNameField.focusNode!.hasFocus, isTrue);
  });

  testWidgets('registers an Individual account with phone, full name, and code', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name (Mandatory)'), 'Asha Patel');
    await tester.tap(find.text('Individual'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(authRepo.registerCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedFullName, 'Asha Patel');
    expect(authRepo.capturedCode, '1234');
  });

  testWidgets('selecting Hospital/Rehab shows the organisation fields, relabeled to Contact person name',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    expect(find.text('Full name (Mandatory)'), findsOneWidget);
    expect(find.text('Organisation Details'), findsNothing);

    await tester.tap(find.text('Hospital / Rehab'));
    await tester.pumpAndSettle();

    expect(find.text('Contact person name (Mandatory)'), findsOneWidget);
    expect(find.text('Full name (Mandatory)'), findsNothing);
    expect(find.text('Organisation Details'), findsOneWidget);
    expect(find.text('Organisation name (Mandatory)'), findsOneWidget);
    expect(find.text('Type of organisation (Mandatory)'), findsOneWidget);
    expect(find.text('City (Mandatory)'), findsOneWidget);
    expect(find.text('Area (Mandatory)'), findsOneWidget);
  });

  testWidgets(
      'tapping Register for Hospital/Rehab with the org fields empty highlights them red and does not submit',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.tap(find.text('Hospital / Rehab'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Contact person name (Mandatory)'), 'Ravi Sharma');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.text('Organisation name is required'), findsOneWidget);
    expect(find.text('Select a type of organisation'), findsOneWidget);
    expect(find.text('Please select a city'), findsOneWidget);
    expect(find.text('Area is required'), findsOneWidget);
    expect(authRepo.registerOrganisationCalled, isFalse);
  });

  testWidgets('registers an Organisation account with all its fields', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name (Mandatory)'), 'Ravi Sharma');
    await tester.tap(find.text('Hospital / Rehab'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Organisation name (Mandatory)'), 'City Hospital');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of organisation (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hospital').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(authRepo.registerOrganisationCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedContactPersonName, 'Ravi Sharma');
    expect(authRepo.capturedOrganisationName, 'City Hospital');
    expect(authRepo.capturedOrganisationType, 'hospital');
    expect(authRepo.capturedCity, 'bangalore');
    expect(authRepo.capturedArea, 'Indiranagar');
  });

  testWidgets('offers Others as a city option for organisations, distinct from the shared City enum',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);
    await tester.tap(find.text('Hospital / Rehab'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();

    expect(find.text('Others').last, findsOneWidget);
  });

  testWidgets('shows the server error message for registration failures', (tester) async {
    final authRepo = _FakeAuthRepository(
      registerError: const ApiException(code: 'AUTH_001', message: 'Phone number is already registered'),
    );
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Full name (Mandatory)'), 'Asha Patel');
    await tester.tap(find.text('Individual'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.text('Phone number is already registered'), findsOneWidget);
  });
}
