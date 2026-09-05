import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/individual_messages/individual_messages_repository.dart';
import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_model.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/profile_screen.dart';
import 'package:nursenow_app/features/organisation/data/organisation_model.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

class _FakeIndividualRepository extends IndividualRepository {
  String? updatedName;
  String? updatedCode;
  final ApiException? nameError;
  final ApiException? codeError;

  _FakeIndividualRepository({this.nameError, this.codeError}) : super(Dio());

  // Overridden so a post-save session refresh (loadSession() -> getMe())
  // never makes a real, unmocked Dio call in a widget test.
  @override
  Future<IndividualModel> getMe() async => IndividualModel(
        userId: 'individual-1',
        fullName: updatedName ?? 'Asha Patel',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );

  @override
  Future<void> updateName(String fullName) async {
    if (nameError != null) throw nameError!;
    updatedName = fullName;
  }

  @override
  Future<void> updateCode(String code) async {
    if (codeError != null) throw codeError!;
    updatedCode = code;
  }

  // Only exercised via MessagesBellButton, embedded in this screen's AppBar
  // for a non-organisation session — irrelevant to what this file actually
  // tests (name/phone/PIN self-edit), so both return empty rather than
  // hitting the real network.
  @override
  Future<List<JobModel>> listMyRequirements() async => const [];

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => const [];
}

/// Empty on purpose — see the fake above's own note.
class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  _FakeIndividualMessagesRepository() : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async => const [];
}

class _FakeOrganisationRepository extends OrganisationRepository {
  String? updatedFullName;
  String? updatedOrganisationName;
  String? updatedOrganisationType;
  String? updatedCity;
  String? updatedArea;
  final ApiException? profileError;

  _FakeOrganisationRepository({this.profileError}) : super(Dio());

  // Overridden so a post-save session refresh (loadSession() -> getMe())
  // never makes a real, unmocked Dio call in a widget test — reflects
  // whatever updateProfile() was last called with, same pattern as
  // _FakeIndividualRepository.getMe() above.
  @override
  Future<OrganisationModel> getMe() async => OrganisationModel(
        userId: 'org-1',
        organisationName: updatedOrganisationName ?? 'City Hospital',
        contactPersonName: updatedFullName ?? 'Ravi Sharma',
        organisationType: updatedOrganisationType ?? 'hospital',
        city: updatedCity ?? 'bangalore',
        area: updatedArea ?? 'Indiranagar',
        phone: '+919876543210',
        isJobPostingBlocked: false,
      );

  @override
  Future<void> updateProfile({
    String? fullName,
    String? organisationName,
    String? organisationType,
    String? city,
    String? area,
  }) async {
    if (profileError != null) throw profileError!;
    updatedFullName = fullName;
    updatedOrganisationName = organisationName;
    updatedOrganisationType = organisationType;
    updatedCity = city;
    updatedArea = area;
  }

  // Only exercised via a post-save session refresh — irrelevant to what
  // this file tests, so it returns empty rather than hitting the network.
  @override
  Future<List<OrganisationRequirementModel>> listMyRequirements() async => const [];
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
  // Full Name section + Login PIN section plus Logout — taller than the
  // default 800x600 surface's viewport + cache extent, so the ListView
  // never mounts the later sections without a taller surface (same
  // reasoning as the standalone "logging out" test below, which already
  // needed this).
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  // A real access token so a post-save loadSession() (triggered after
  // saving the name/PIN) re-hydrates via the fake repo's getMe() instead of
  // falling through to SessionUnauthenticated — which would otherwise show
  // an indefinitely-animating loading spinner that pumpAndSettle can never
  // settle on.
  await localStorage.saveTokens(accessToken: 'test-token', refreshToken: 'test-refresh');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        individualMessagesRepositoryProvider.overrideWithValue(_FakeIndividualMessagesRepository()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
              patientNumber: 500,
            ),
        ),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// A minimal JWT-shaped (but unsigned) token with a `role` claim —
/// SessionNotifier.loadSession() decodes this client-side (no signature
/// verification) purely to decide whether to hydrate via
/// OrganisationRepository or IndividualRepository. A plain non-JWT string
/// like 'test-token' (fine for Individual, since decode failure falls back
/// to the individual path) would silently take the WRONG branch here and
/// hit the unmocked IndividualRepository, hanging the test.
String _fakeJwt(Map<String, dynamic> payload) {
  String segment(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${segment({'alg': 'none'})}.${segment(payload)}.signature';
}

Future<void> _pumpOrganisation(WidgetTester tester, _FakeOrganisationRepository repo) async {
  // Organisation Details (5 fields) + Phone/PIN sections + Logout — taller
  // than the default viewport, same reasoning as _pump above.
  await tester.binding.setSurfaceSize(const Size(400, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await localStorage.saveTokens(
    accessToken: _fakeJwt({'role': 'organisation'}),
    refreshToken: 'test-refresh',
  );
  final individualRepo = IndividualRepository(Dio());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        organisationRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, individualRepo, repo)
            ..state = const SessionAuthenticated(
              role: 'organisation',
              fullName: 'Ravi Sharma',
              phone: '+919876543210',
              isJobPostingBlocked: false,
              organisationName: 'City Hospital',
              organisationType: 'hospital',
              city: 'bangalore',
              area: 'Indiranagar',
            ),
        ),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the account name and phone (read-only) with a pointer to the Help button', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    // Appears twice — once in the header, once prefilled into the new Full
    // Name field below (find.text matches EditableText, not just Text).
    expect(find.text('Asha Patel'), findsNWidgets(2));
    // Phone is shown exactly once now — just in the header row, no separate
    // "Phone Number" section duplicating it further down.
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Phone number'), findsNothing);
    expect(find.text('Phone Number'), findsNothing);
    expect(find.textContaining('tap the Help button above to chat with us on WhatsApp'), findsOneWidget);
    expect(find.text('PAT-500'), findsOneWidget);
  });

  testWidgets('shows the account name prefilled into the Full Name field', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    final nameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Full name'));
    expect(nameField.controller?.text, 'Asha Patel');
  });

  testWidgets('saving a valid name calls the repository and shows a success message', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pump(tester, repo);

    final nameField = find.widgetWithText(TextField, 'Full name');
    await tester.enterText(nameField, 'Asha P Patel');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Name'));
    await tester.pumpAndSettle();

    expect(repo.updatedName, 'Asha P Patel');
    expect(find.text('Name updated.'), findsOneWidget);
  });

  testWidgets('rejects an invalid name without calling the repository', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Name'));
    await tester.pumpAndSettle();

    expect(repo.updatedName, isNull);
    expect(find.text('Enter a valid name (letters and spaces only)'), findsOneWidget);
  });

  testWidgets('shows a server error message when the name save fails', (tester) async {
    final repo = _FakeIndividualRepository(
      nameError: const ApiException(code: 'PROFILE_020', message: 'Name can only contain letters and spaces'),
    );
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha P Patel');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Name'));
    await tester.pumpAndSettle();

    expect(find.text('Name can only contain letters and spaces'), findsOneWidget);
    expect(repo.updatedName, isNull);
  });

  testWidgets('shows a blocked-posting notice when is_job_posting_blocked is true', (tester) async {
    await _pump(tester, _FakeIndividualRepository(), isJobPostingBlocked: true);

    expect(find.textContaining('Posting new requirements is currently blocked'), findsOneWidget);
  });

  testWidgets('saving a valid 4-digit PIN calls the repository and shows a success message', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'New 4-digit PIN'), '4321');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save PIN'));
    await tester.pumpAndSettle();

    expect(repo.updatedCode, '4321');
    expect(find.text('PIN updated.'), findsOneWidget);
  });

  testWidgets('rejects a PIN that is not exactly 4 digits without calling the repository', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'New 4-digit PIN'), '12');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save PIN'));
    await tester.pumpAndSettle();

    expect(repo.updatedCode, isNull);
    expect(find.text('PIN must be exactly 4 digits'), findsOneWidget);
  });

  testWidgets('shows a server error message when the PIN save fails', (tester) async {
    final repo = _FakeIndividualRepository(codeError: const ApiException(code: 'GEN_003', message: 'Could not reach the server.'));
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'New 4-digit PIN'), '4321');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(repo.updatedCode, isNull);
  });

  testWidgets('logging out clears the session and navigates to /login', (tester) async {
    // The Logout button sits below two full form sections — tall enough to
    // fall outside the default 800x600 surface's viewport + cache extent,
    // so the ListView's sliver never mounts it without a taller surface.
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeIndividualRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          individualRepositoryProvider.overrideWithValue(repo),
          individualMessagesRepositoryProvider.overrideWithValue(_FakeIndividualMessagesRepository()),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
              ..state = const SessionAuthenticated(
                role: 'individual',
                fullName: 'Asha Patel',
                phone: '+919876543210',
                isJobPostingBlocked: false,
              ),
          ),
        ],
        child: MaterialApp(
          home: const ProfileScreen(),
          routes: {'/login': (_) => const Scaffold(body: Text('login screen'))},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(find.text('login screen'), findsOneWidget);
  });

  group('Organisation account — Organisation Details self-edit', () {
    testWidgets('prefills every field from the session, and shows no Full Name section (that\'s Individual-only)',
        (tester) async {
      await _pumpOrganisation(tester, _FakeOrganisationRepository());

      expect(find.text('Organisation Details'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Contact person name'), findsOneWidget);
      final contactField = tester.widget<TextField>(find.widgetWithText(TextField, 'Contact person name'));
      expect(contactField.controller?.text, 'Ravi Sharma');
      final orgNameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Organisation name'));
      expect(orgNameField.controller?.text, 'City Hospital');
      final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Optional)'));
      expect(areaField.controller?.text, 'Indiranagar');
      expect(find.text('Hospital'), findsWidgets);
      expect(find.text('Bangalore'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Full name'), findsNothing);
    });

    testWidgets('saving every field calls updateProfile with all of them and shows a success message',
        (tester) async {
      final repo = _FakeOrganisationRepository();
      await _pumpOrganisation(tester, repo);

      await tester.enterText(find.widgetWithText(TextField, 'Contact person name'), 'Priya Iyer');
      await tester.enterText(find.widgetWithText(TextField, 'Organisation name'), 'Green Valley Clinic');
      await tester.enterText(find.widgetWithText(TextField, 'Area (Optional)'), 'Whitefield');

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Type of organisation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clinic').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'City'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mumbai').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Organisation Details'));
      await tester.pumpAndSettle();

      expect(repo.updatedFullName, 'Priya Iyer');
      expect(repo.updatedOrganisationName, 'Green Valley Clinic');
      expect(repo.updatedOrganisationType, 'clinic');
      expect(repo.updatedCity, 'mumbai');
      expect(repo.updatedArea, 'Whitefield');
      expect(find.text('Organisation details updated.'), findsOneWidget);
    });

    testWidgets('rejects an invalid contact person name without calling the repository', (tester) async {
      final repo = _FakeOrganisationRepository();
      await _pumpOrganisation(tester, repo);

      await tester.enterText(find.widgetWithText(TextField, 'Contact person name'), 'Priya123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Organisation Details'));
      await tester.pumpAndSettle();

      expect(repo.updatedFullName, isNull);
      expect(find.text('Enter a valid contact person name (letters and spaces only)'), findsOneWidget);
    });

    testWidgets('rejects a blank organisation name without calling the repository', (tester) async {
      final repo = _FakeOrganisationRepository();
      await _pumpOrganisation(tester, repo);

      await tester.enterText(find.widgetWithText(TextField, 'Organisation name'), '');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Organisation Details'));
      await tester.pumpAndSettle();

      expect(repo.updatedFullName, isNull);
      expect(find.text('Organisation name is required'), findsOneWidget);
    });

    testWidgets('shows a server error message when the org profile save fails', (tester) async {
      final repo = _FakeOrganisationRepository(
        profileError: const ApiException(code: 'GEN_001', message: 'Invalid or missing field'),
      );
      await _pumpOrganisation(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Organisation Details'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or missing field'), findsOneWidget);
    });
  });
}
