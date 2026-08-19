import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String? updatedPhone;
  String? updatedCode;
  final ApiException? phoneError;
  final ApiException? codeError;

  _FakeIndividualRepository({this.phoneError, this.codeError}) : super(Dio());

  // Overridden so a post-save session refresh (loadSession() -> getMe())
  // never makes a real, unmocked Dio call in a widget test.
  @override
  Future<IndividualModel> getMe() async => IndividualModel(
        userId: 'individual-1',
        fullName: 'Asha Patel',
        phone: updatedPhone ?? '+919876543210',
        isJobPostingBlocked: false,
      );

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
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
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
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
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

    expect(find.text('Asha Patel'), findsOneWidget);
    final phoneField = tester.widget<TextField>(find.widgetWithText(TextField, 'Phone number'));
    expect(phoneField.controller?.text, '+919876543210');
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
