import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/core/duty_requirements/duty_requirements_repository.dart';
import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/rate_card/rate_card_repository.dart';
import 'package:nursenow_app/patient_hospital/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/auth/data/auth_repository.dart';
import 'package:nursenow_app/patient_hospital/features/auth/data/auth_result.dart';
import 'package:nursenow_app/patient_hospital/features/auth/screens/registration_screen.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_model.dart';

/// Always exactly one row ("Care") per frequency, matching the live shape.
RateCardModel _rateCard({required String frequencyOfCare, required String companion}) => RateCardModel(
      frequencyOfCare: frequencyOfCare,
      title: 'Salary Guidelines',
      columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
      rowLabels: const ['Care'],
      cells: [
        [companion, 'BEDSIDE_RATE', 'CRITICAL_RATE'],
      ],
    );

/// Covers both frequencies with a Companion-tier default so
/// _fillIndividualMandatoryFields' default (independent/oral-feeding, Few
/// Weeks -> daily) auto-suggests a real, non-empty Salary without every
/// test having to type one in manually.
final _defaultRateCards = [
  _rateCard(frequencyOfCare: FrequencyOfCare.daily, companion: 'DAILY_COMPANION_RATE'),
  _rateCard(frequencyOfCare: FrequencyOfCare.monthly, companion: 'MONTHLY_COMPANION_RATE'),
];

class _FakeRateCardRepository extends RateCardRepository {
  final List<RateCardModel>? result;

  _FakeRateCardRepository({this.result}) : super(Dio());

  @override
  Future<List<RateCardModel>> get() async => result ?? const [];
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => ScopeOfWorkModel(
        companionCare: const ['Companion bullet'],
        bedsideCare: const ['Bedside bullet'],
        criticalCare: const ['Critical bullet'],
      );
}

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  _FakeDutyRequirementsRepository() : super(Dio());

  @override
  Future<DutyRequirementsModel> get() async => const DutyRequirementsModel(
        liveIn: ['Live-in bullet'],
        dayDuty: ['Day-duty bullet'],
        nightDuty: ['Night-duty bullet'],
      );
}

class _FakeAuthRepository extends AuthRepository {
  final ApiException? registerError;
  bool registerCalled = false;
  bool registerOrganisationCalled = false;
  String? capturedPhone;
  String? capturedFullName;
  String? capturedCode;
  String? capturedPhoneVerificationToken;
  String? capturedOrganisationName;
  String? capturedContactPersonName;
  String? capturedOrganisationType;
  String? capturedCity;
  String? capturedArea;
  String? capturedOtpPurpose;
  String verifyOtpReturnValue = 'verified-token';
  bool throwOnSendOtp = false;
  bool throwOnVerifyOtp = false;

  _FakeAuthRepository({this.registerError}) : super(Dio());

  bool? capturedTermsAccepted;

  @override
  Future<AuthResult> register({
    required String phone,
    required bool termsAccepted,
    String? fullName,
    String? code,
    String? phoneVerificationToken,
  }) async {
    registerCalled = true;
    capturedPhone = phone;
    capturedFullName = fullName;
    capturedTermsAccepted = termsAccepted;
    capturedCode = code;
    capturedPhoneVerificationToken = phoneVerificationToken;
    if (registerError != null) throw registerError!;
    return const AuthResult(userId: 'u1', accessToken: 'access', refreshToken: 'refresh');
  }

  @override
  Future<AuthResult> registerOrganisation({
    required String phone,
    required String organisationName,
    required String contactPersonName,
    required String organisationType,
    required String city,
    String? area,
    required bool termsAccepted,
    String? code,
    String? phoneVerificationToken,
  }) async {
    registerOrganisationCalled = true;
    capturedPhone = phone;
    capturedCode = code;
    capturedPhoneVerificationToken = phoneVerificationToken;
    capturedOrganisationName = organisationName;
    capturedContactPersonName = contactPersonName;
    capturedOrganisationType = organisationType;
    capturedCity = city;
    capturedArea = area;
    capturedTermsAccepted = termsAccepted;
    if (registerError != null) throw registerError!;
    return const AuthResult(userId: 'org-1', accessToken: 'access', refreshToken: 'refresh');
  }

  @override
  Future<void> sendOtp({required String phone, required String purpose}) async {
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
}

class _FakeIndividualRepository extends IndividualRepository {
  // One-shot: thrown on the first createRequirement call, then cleared —
  // lets a retry-after-failure test exercise a second attempt succeeding.
  ApiException? createError;
  bool createCalled = false;
  CareReceiverInput? capturedCareReceiver;
  String? capturedCity;
  String? capturedArea;
  String? capturedDutyType;
  String? capturedCareDuration;
  List<String>? capturedLanguages;
  String? capturedFrequencyOfCare;
  String? capturedSalaryAmount;

  _FakeIndividualRepository({this.createError}) : super(Dio());

  @override
  Future<IndividualModel> getMe() async => const IndividualModel(
        userId: 'u1',
        fullName: '+919876543210',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );

  @override
  Future<JobModel> createRequirement({
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required String careDuration,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    required String frequencyOfCare,
    required String salaryAmount,
  }) async {
    createCalled = true;
    capturedCareReceiver = careReceiver;
    capturedCity = city;
    capturedArea = area;
    capturedDutyType = dutyType;
    capturedCareDuration = careDuration;
    capturedLanguages = languages;
    capturedFrequencyOfCare = frequencyOfCare;
    capturedSalaryAmount = salaryAmount;
    if (createError != null) {
      final error = createError!;
      createError = null;
      throw error;
    }
    return JobModel.fromJson({
      'id': 'job-1',
      'city': city,
      'duty_type': dutyType,
      'frequency_of_care': frequencyOfCare,
      'languages': languages,
      'salary_amount': salaryAmount,
      'status': 'pending_review',
      'posted_by': 'individual-1',
      'posted_at': '2026-08-01T10:00:00Z',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pumpRegistration(
  WidgetTester tester, {
  required _FakeAuthRepository authRepo,
  _FakeIndividualRepository? individualRepo,
  bool otpMode = false,
  bool startAsOrganisation = false,
  List<RateCardModel>? rateCards,
}) async {
  // The merged Individual form (registration + full requirement fields)
  // and the Organisation fields both push well past the default 800x600
  // viewport + cache extent — a plain ListView's sliver won't mount
  // widgets that far below the fold without a taller surface.
  await tester.binding.setSurfaceSize(const Size(400, 4200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        authRepositoryProvider.overrideWithValue(authRepo),
        individualRepositoryProvider.overrideWithValue(individualRepo ?? _FakeIndividualRepository()),
        rateCardRepositoryProvider.overrideWithValue(_FakeRateCardRepository(result: rateCards ?? _defaultRateCards)),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        dutyRequirementsRepositoryProvider.overrideWithValue(_FakeDutyRequirementsRepository()),
        otpModeProvider.overrideWith((ref) => otpMode),
      ],
      child: MaterialApp(
        home: RegistrationScreen(startAsOrganisation: startAsOrganisation),
        routes: {'/home': (_) => const Scaffold(body: Text('home'))},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fills every mandatory field on the Individual (patient/family) branch
/// except phone/PIN/terms — the merged-in requirement-posting fields.
Future<void> _fillIndividualMandatoryFields(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '74');
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, "Patient's Gender (Mandatory)"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Female').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), '58');

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bangalore').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('24Hrs - Live In').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(OutlinedButton, 'Select date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Need for Few Weeks').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Independent/minimal support').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Oral feeding').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Register is always tappable; tapping it with every mandatory field empty highlights all of them (Individual + terms) in red and does not submit',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    final individualRepo = _FakeIndividualRepository();
    await _pumpRegistration(tester, authRepo: authRepo, individualRepo: individualRepo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(find.text('Enter a 4-digit PIN'), findsOneWidget);
    expect(find.text('Age is required (1-120)'), findsOneWidget);
    expect(find.text('Please select a gender'), findsOneWidget);
    expect(find.text('Weight is required (1-300 kg)'), findsOneWidget);
    expect(find.text('Please select a city'), findsOneWidget);
    expect(find.text('Area is required'), findsOneWidget);
    expect(find.text('Please select duty hours'), findsOneWidget);
    expect(find.text('Select a preferred start date'), findsOneWidget);
    expect(find.text('Please select how long care is needed'), findsOneWidget);
    expect(find.text('You must accept the Terms & Conditions to continue'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
    expect(individualRepo.createCalled, isFalse);
  });

  testWidgets('tapping Register without accepting terms highlights it red and does not submit', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    // Terms checkbox and the job fields are deliberately left blank — this
    // only checks that the terms error specifically appears when missing.

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('You must accept the Terms & Conditions to continue'), findsOneWidget);
    expect(authRepo.registerCalled, isFalse);
  });

  testWidgets('Contact person name is capped at 24 characters (Organisation only)', (tester) async {
    await _pumpRegistration(tester, authRepo: _FakeAuthRepository(), startAsOrganisation: true);

    final fullNameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Contact person name (Mandatory)'));
    expect(fullNameField.maxLength, Validation.nameMaxLength);
  });

  testWidgets('Individual submit button says Post Requirement; Organisation still says Register', (tester) async {
    await _pumpRegistration(tester, authRepo: _FakeAuthRepository());
    expect(find.widgetWithText(ElevatedButton, 'Post Requirement'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Register'), findsNothing);
  });

  testWidgets('Individual (the default) shows no name field, no Organisation Details, and the full requirement form',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    expect(find.text('Full name (Mandatory)'), findsNothing);
    expect(find.text('Contact person name (Mandatory)'), findsNothing);
    expect(find.text('Organisation Details'), findsNothing);
    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.text('Care Preferences'), findsOneWidget);
  });

  testWidgets('Terms & Conditions checkbox sits below the requirement fields, not above them', (tester) async {
    await _pumpRegistration(tester, authRepo: _FakeAuthRepository());

    final carePreferencesY = tester.getTopLeft(find.text('Care Preferences')).dy;
    final termsY = tester.getTopLeft(find.byKey(const Key('termsCheckbox'))).dy;
    expect(termsY, greaterThan(carePreferencesY));
  });

  testWidgets('registers an Individual account AND posts its one requirement in a single submit', (tester) async {
    final authRepo = _FakeAuthRepository();
    final individualRepo = _FakeIndividualRepository();
    await _pumpRegistration(tester, authRepo: authRepo, individualRepo: individualRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await _fillIndividualMandatoryFields(tester);
    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(authRepo.registerCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedFullName, isNull);
    expect(authRepo.capturedTermsAccepted, isTrue);
    expect(authRepo.capturedCode, '1234');

    expect(individualRepo.createCalled, isTrue);
    expect(individualRepo.capturedCity, 'bangalore');
    expect(individualRepo.capturedArea, 'Indiranagar');
    expect(individualRepo.capturedDutyType, DutyType.liveIn);
    expect(individualRepo.capturedCareDuration, CareDuration.fewWeeks);
    expect(individualRepo.capturedFrequencyOfCare, FrequencyOfCare.daily);
    expect(individualRepo.capturedSalaryAmount, 'DAILY_COMPANION_RATE');
    expect(individualRepo.capturedCareReceiver!.age, 74);
    expect(individualRepo.capturedCareReceiver!.gender, Gender.female);
    expect(individualRepo.capturedCareReceiver!.weightKg, 58);
    // "None" selections were never shown to the patient as such on
    // submission — Toilet Assistance/Feeding were both explicitly picked
    // as real values here, so no translation is exercised by this test;
    // see the dedicated "None" test below.

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('"None" for Feeding/Toilet Assistance submits the same values and salary as their real equivalents',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    final individualRepo = _FakeIndividualRepository();
    await _pumpRegistration(tester, authRepo: authRepo, individualRepo: individualRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');

    await tester.enterText(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), '74');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, "Patient's Gender (Mandatory)"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, "Patient's Weight (kg) (Mandatory)"), '58');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Area (Mandatory)'), 'Indiranagar');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hours Care Needed (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24Hrs - Live In').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'How long you need the care for? (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need for Few Weeks').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toilet Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Feeding/Medicine Assistance (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(individualRepo.createCalled, isTrue);
    expect(individualRepo.capturedCareReceiver!.feedingType, FeedingType.oralFeeding);
    expect(individualRepo.capturedCareReceiver!.toiletAssistance, [ToiletAssistance.independent]);
    expect(individualRepo.capturedSalaryAmount, 'DAILY_COMPANION_RATE');
  });

  testWidgets(
      'reaching this screen via the Organisation row (startAsOrganisation: true) shows the organisation '
      'fields immediately, relabeled to Contact person name — there is no in-form toggle', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo, startAsOrganisation: true);

    expect(find.text('Contact person name (Mandatory)'), findsOneWidget);
    expect(find.text('Full name (Mandatory)'), findsNothing);
    expect(find.byKey(const Key('registerAsOrganisationCheckbox')), findsNothing);
    expect(find.text('Organisation Details'), findsOneWidget);
    expect(find.text('Organisation name (Mandatory)'), findsOneWidget);
    expect(find.text('Type of organisation (Mandatory)'), findsOneWidget);
    expect(find.text('City (Mandatory)'), findsOneWidget);
    expect(find.text('Area (Optional)'), findsOneWidget);
    expect(find.text('Patient Details'), findsNothing);
  });

  testWidgets(
      'tapping Register for Hospital/Rehab with the org fields empty highlights them red and does not submit',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo, startAsOrganisation: true);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Contact person name (Mandatory)'), 'Ravi Sharma');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.text('Organisation name is required'), findsOneWidget);
    expect(find.text('Select a type of organisation'), findsOneWidget);
    expect(find.text('Please select a city'), findsOneWidget);
    expect(authRepo.registerOrganisationCalled, isFalse);
  });

  testWidgets('registers an Organisation account with all its fields', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo, startAsOrganisation: true);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Contact person name (Mandatory)'), 'Ravi Sharma');

    await tester.enterText(find.widgetWithText(TextField, 'Organisation name (Mandatory)'), 'City Hospital');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of organisation (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hospital').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Area (Optional)'), 'Indiranagar');
    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(authRepo.registerOrganisationCalled, isTrue);
    expect(authRepo.capturedPhone, '+919876543210');
    expect(authRepo.capturedContactPersonName, 'Ravi Sharma');
    expect(authRepo.capturedOrganisationName, 'City Hospital');
    expect(authRepo.capturedOrganisationType, 'hospital');
    expect(authRepo.capturedCity, 'bangalore');
    expect(authRepo.capturedArea, 'Indiranagar');
    expect(authRepo.capturedTermsAccepted, isTrue);
  });

  testWidgets('registers an Organisation account with Area left blank — it is optional, not required',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo, startAsOrganisation: true);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Contact person name (Mandatory)'), 'Ravi Sharma');

    await tester.enterText(find.widgetWithText(TextField, 'Organisation name (Mandatory)'), 'City Hospital');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of organisation (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agency').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bangalore').last);
    await tester.pumpAndSettle();

    // Area left untouched.
    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(authRepo.registerOrganisationCalled, isTrue);
    expect(authRepo.capturedOrganisationType, 'agency');
    expect(authRepo.capturedArea, isNull);
  });

  testWidgets('offers Others as a city option for organisations, distinct from the shared City enum',
      (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo, startAsOrganisation: true);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
    await tester.pumpAndSettle();

    expect(find.text('Others').last, findsOneWidget);
  });

  testWidgets('shows the server error message for a registration failure (Individual)', (tester) async {
    final authRepo = _FakeAuthRepository(
      registerError: const ApiException(code: 'AUTH_001', message: 'Phone number is already registered'),
    );
    await _pumpRegistration(tester, authRepo: authRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await _fillIndividualMandatoryFields(tester);
    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Phone number is already registered'), findsOneWidget);
  });

  testWidgets('a requirement-posting failure after a successful registration can be retried by tapping submit again — '
      'the account is not re-registered', (tester) async {
    final authRepo = _FakeAuthRepository();
    final individualRepo = _FakeIndividualRepository(
      createError: const ApiException(code: 'GEN_003', message: 'Internal server error'),
    );
    await _pumpRegistration(tester, authRepo: authRepo, individualRepo: individualRepo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
    await tester.enterText(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), '1234');
    await _fillIndividualMandatoryFields(tester);
    await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(authRepo.registerCalled, isTrue);
    expect(individualRepo.createCalled, isTrue);
    expect(find.text('Internal server error'), findsOneWidget);
    expect(find.text('home'), findsNothing);

    // Retry: tapping submit again should NOT call register() a second
    // time (the account already exists and is logged in) — only
    // createRequirement is retried.
    authRepo.registerCalled = false;
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
    await tester.pumpAndSettle();

    expect(authRepo.registerCalled, isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('shows a Terms & Conditions checkbox with a tappable link to the terms document', (tester) async {
    final authRepo = _FakeAuthRepository();
    await _pumpRegistration(tester, authRepo: authRepo);

    expect(find.byKey(const Key('termsCheckbox')), findsOneWidget);
    expect(find.textContaining('Terms & Conditions', findRichText: true), findsOneWidget);
  });

  group('OTP mode', () {
    testWidgets('shows "Send OTP to verify" instead of the 4-digit PIN field', (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpRegistration(tester, authRepo: authRepo, otpMode: true);

      expect(find.widgetWithText(TextField, 'Create a 4-digit PIN (Mandatory)'), findsNothing);
      expect(find.text('Send OTP to verify'), findsOneWidget);
    });

    testWidgets('tapping Send OTP calls sendOtp with purpose register and reveals the OTP field', (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpRegistration(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
      await tester.tap(find.text('Send OTP to verify'));
      await tester.pumpAndSettle();

      expect(authRepo.capturedOtpPurpose, OtpPurpose.register);
      expect(find.widgetWithText(TextField, '6-digit OTP'), findsOneWidget);
    });

    testWidgets(
        'registers an Individual account with a verified phone and posts its requirement, sending '
        'phoneVerificationToken and no code', (tester) async {
      final authRepo = _FakeAuthRepository();
      final individualRepo = _FakeIndividualRepository();
      await _pumpRegistration(tester, authRepo: authRepo, individualRepo: individualRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
      await tester.tap(find.text('Send OTP to verify'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6-digit OTP'), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Phone number verified'), findsOneWidget);

      await _fillIndividualMandatoryFields(tester);
      await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Post Requirement'));
      await tester.pumpAndSettle();

      expect(authRepo.registerCalled, isTrue);
      expect(authRepo.capturedCode, isNull);
      expect(authRepo.capturedPhoneVerificationToken, 'verified-token');
      expect(individualRepo.createCalled, isTrue);
    });

    testWidgets(
        'registers an Organisation account with a verified phone, sending phoneVerificationToken and no code',
        (tester) async {
      final authRepo = _FakeAuthRepository();
      await _pumpRegistration(tester, authRepo: authRepo, otpMode: true, startAsOrganisation: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
      await tester.tap(find.text('Send OTP to verify'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6-digit OTP'), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Contact person name (Mandatory)'), 'Ravi Sharma');
      await tester.enterText(find.widgetWithText(TextField, 'Organisation name (Mandatory)'), 'City Hospital');
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of organisation (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hospital').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City (Mandatory)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bangalore').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Area (Optional)'), 'Indiranagar');
      await tester.tap(find.descendant(of: find.byKey(const Key('termsCheckbox')), matching: find.byType(Checkbox)));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
      await tester.pumpAndSettle();

      expect(authRepo.registerOrganisationCalled, isTrue);
      expect(authRepo.capturedCode, isNull);
      expect(authRepo.capturedPhoneVerificationToken, 'verified-token');
    });

    testWidgets('shows the server error when sendOtp fails', (tester) async {
      final authRepo = _FakeAuthRepository()..throwOnSendOtp = true;
      await _pumpRegistration(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
      await tester.tap(find.text('Send OTP to verify'));
      await tester.pumpAndSettle();

      expect(find.text('Please wait before requesting another code'), findsOneWidget);
    });

    testWidgets('shows the server error when verifyOtp fails', (tester) async {
      final authRepo = _FakeAuthRepository()..throwOnVerifyOtp = true;
      await _pumpRegistration(tester, authRepo: authRepo, otpMode: true);

      await tester.enterText(find.widgetWithText(TextField, 'Phone number (Mandatory)'), '9876543210');
      await tester.tap(find.text('Send OTP to verify'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6-digit OTP'), '000000');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or expired OTP'), findsOneWidget);
      expect(find.text('Phone number verified'), findsNothing);
    });
  });
}
