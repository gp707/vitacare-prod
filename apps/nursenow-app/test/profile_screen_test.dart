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
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

class _FakeIndividualRepository extends IndividualRepository {
  String? updatedName;
  String? updatedPhone;
  String? updatedCode;
  final ApiException? nameError;
  final ApiException? phoneError;
  final ApiException? codeError;

  _FakeIndividualRepository({this.nameError, this.phoneError, this.codeError}) : super(Dio());

  // Overridden so a post-save session refresh (loadSession() -> getMe())
  // never makes a real, unmocked Dio call in a widget test.
  @override
  Future<IndividualModel> getMe() async => IndividualModel(
        userId: 'individual-1',
        fullName: updatedName ?? 'Asha Patel',
        phone: updatedPhone ?? '+919876543210',
        isJobPostingBlocked: false,
      );

  @override
  Future<void> updateName(String fullName) async {
    if (nameError != null) throw nameError!;
    updatedName = fullName;
  }

  @override
  Future<void> updatePhone(String phone) async {
    if (phoneError != null) throw phoneError!;
    updatedPhone = phone;
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

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
  // Now 3 full form sections (Full Name/Phone Number/Login PIN) plus
  // Logout — taller than the default 800x600 surface's viewport + cache
  // extent, so the ListView never mounts the later sections without a
  // taller surface (same reasoning as the standalone "logging out" test
  // below, which already needed this).
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  // A real access token so a post-save loadSession() (triggered after
  // saving the phone number) re-hydrates via the fake repo's getMe()
  // instead of falling through to SessionUnauthenticated — which would
  // otherwise show an indefinitely-animating loading spinner that
  // pumpAndSettle can never settle on.
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
      // Stub route so a real "Save Phone Number" -> session-refresh doesn't
      // need /home registered — this screen itself never navigates there.
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the account name and phone, prefilled into the phone field', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    // Appears twice — once in the header, once prefilled into the new Full
    // Name field below (find.text matches EditableText, not just Text).
    expect(find.text('Asha Patel'), findsNWidgets(2));
    final phoneField = tester.widget<TextField>(find.widgetWithText(TextField, 'Phone number'));
    expect(phoneField.controller?.text, '+919876543210');
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

  testWidgets('saving a valid phone number calls the repository and shows a success message', (tester) async {
    final repo = _FakeIndividualRepository();
    await _pump(tester, repo);

    final phoneField = find.widgetWithText(TextField, 'Phone number');
    await tester.enterText(phoneField, '+919876500000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Phone Number'));
    await tester.pumpAndSettle();

    expect(repo.updatedPhone, '+919876500000');
    expect(find.text('Phone number updated.'), findsOneWidget);
  });

  testWidgets('shows a server error message when the phone save fails', (tester) async {
    final repo = _FakeIndividualRepository(
      phoneError: const ApiException(code: 'AUTH_001', message: 'Phone number is already registered'),
    );
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '+919876500000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Phone Number'));
    await tester.pumpAndSettle();

    expect(find.text('Phone number is already registered'), findsOneWidget);
    expect(repo.updatedPhone, isNull);
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
}
