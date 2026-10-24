// On-device end-to-end flows for the JustHeal binary (patient/family +
// organisation), driven through the real UI against a real backend.
//
// Run (debug build is pointed at a real API via API_BASE_URL — release
// builds always use production, see core/network/api_client.dart):
//
//   flutter test integration_test/app_flows_test.dart -d <device> \
//     --dart-define=API_BASE_URL=https://api.vitacasahealth.in/v1
//
// SAFETY: every account created here uses a phone in the dedicated
// +9170009900xx test range, never touches any other account, never goes
// through admin approval (approval broadcasts a push to real caregivers),
// and deletes itself at the end via the app's own "Delete My Account".
// Caregiver registration is not covered: it needs a live camera selfie
// (ImageSource.camera only), which can't be driven in an integration test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nursenow_app/main.dart' as app;
import 'package:nursenow_app/patient_hospital/app/messages_bell.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _individualPhone = '7000990001';
const _organisationPhone = '7000990002';
const _pin = '1234';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps (never pumpAndSettle — blinking badges/animations never settle)
/// until [finder] matches, failing with a clear message after [timeout].
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      // Let any in-flight route transition finish — pointer events are
      // ignored while a page animates in, which makes an immediate tap miss.
      await _pumpFor(tester, const Duration(milliseconds: 900));
      return;
    }
  }
  final visible = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText())
      .whereType<String>()
      .toList();
  fail('Timed out waiting for ${reason ?? finder.toString()}. Visible text: $visible');
}

Future<void> _launchFresh(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  app.main();
  // A cold launch on a loaded emulator can take minutes (Firebase init, JIT
  // warm-up), so this one wait is deliberately far more patient than the rest.
  await _waitFor(tester, find.text('Log in'),
      timeout: const Duration(seconds: 300), reason: 'login screen after cold launch');
}

/// Real device: entering text opens the soft keyboard, which covers the
/// lower part of the screen and swallows taps there. Close it after typing.
Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pickDropdown(WidgetTester tester, String label, String option) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  await _reveal(tester, field);
  await tester.tap(field);
  await _pumpFor(tester, const Duration(milliseconds: 600));
  await tester.tap(find.text(option).last);
  await _pumpFor(tester, const Duration(milliseconds: 600));
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await _reveal(tester, field);
  await tester.enterText(field, text);
  await _dismissKeyboard(tester);
}

Future<void> _acceptTerms(WidgetTester tester) async {
  final tile = find.byKey(const Key('termsCheckbox'));
  await _reveal(tester, tile);
  // Tap the checkbox itself: the middle of the row can land on the
  // underlined "Terms & Conditions" link on narrower screens, which opens
  // the terms page instead of ticking the box.
  await tester.tap(find.descendant(of: tile, matching: find.byType(Checkbox)));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _fillIndividualRegistration(WidgetTester tester, {required String phone}) async {
  await _type(tester, 'Phone number (Mandatory)', phone);
  await _type(tester, 'Create a 4-digit PIN (Mandatory)', _pin);
  await _type(tester, "Patient's Name (Mandatory)", 'Zz Test Patient');
  await _type(tester, "Patient's Age (Mandatory)", '74');
  await _pickDropdown(tester, "Patient's Gender (Mandatory)", 'Female');
  await _type(tester, "Patient's Weight (kg) (Mandatory)", '58');
  await _pickDropdown(tester, 'City (Mandatory)', 'Bangalore');
  await _type(tester, 'Area (Mandatory)', 'Indiranagar');
  await _pickDropdown(tester, 'Hours Care Needed (Mandatory)', '24Hrs - Live In');
  await _pickDropdown(tester, 'How long you need the care for? (Mandatory)', 'Need for Few Weeks');
  await _pickDropdown(tester, 'Toilet Assistance (Mandatory)', 'Independent/minimal support');
  await _pickDropdown(tester, 'Feeding/Medicine Assistance (Mandatory)', 'Oral feeding');
  await _acceptTerms(tester);
}

Future<void> _fillOrganisationRegistration(WidgetTester tester, {required String phone}) async {
  await _type(tester, 'Phone number (Mandatory)', phone);
  await _type(tester, 'Create a 4-digit PIN (Mandatory)', _pin);
  await _type(tester, 'Contact person name (Mandatory)', 'Zz Test Contact');
  await _type(tester, 'Organisation name (Mandatory)', 'Zz Test Org');
  await _pickDropdown(tester, 'Type of organisation (Mandatory)', 'Hospital');
  await _pickDropdown(tester, 'City (Mandatory)', 'Bangalore');
  await _acceptTerms(tester);
}

Future<void> _login(WidgetTester tester, {required String phone, required String pin}) async {
  final phoneField = find.widgetWithText(TextField, 'Phone number');
  final pinField = find.widgetWithText(TextField, '4-digit code');
  await _reveal(tester, phoneField);
  await tester.enterText(phoneField, phone);
  await _dismissKeyboard(tester);
  await tester.enterText(pinField, pin);
  await _dismissKeyboard(tester);
  final button = find.widgetWithText(ElevatedButton, 'Log in');
  await _reveal(tester, button);
  await tester.tap(button);
}

/// The hidden logout gesture: 3 quick taps on the AppBar logo.
Future<void> _logoutViaLogoTripleTap(WidgetTester tester) async {
  final logo = find.byType(Image).first;
  for (var i = 0; i < 3; i++) {
    await tester.tap(logo);
    await tester.pump(const Duration(milliseconds: 120));
  }
  await _waitFor(tester, find.text('Log in'), reason: 'login screen after triple-tap logout');
}


/// Simulates force-closing the app and reopening it: tears the whole widget
/// tree down, makes SharedPreferences re-read from disk (a fresh process has
/// no in-memory cache), and runs main() again WITHOUT clearing storage — so
/// whatever the splash screen decides comes purely from what was persisted.
/// (A real process kill can't be done from inside a test.)
Future<void> _forceCloseAndReopen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpFor(tester, const Duration(milliseconds: 500));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.resetStatic();
  app.main();
}

/// After a reopen, the user must go straight to [home] without ever seeing
/// the login screen.
Future<void> _expectStillLoggedInAfterReopen(WidgetTester tester, String home) async {
  await _forceCloseAndReopen(tester);
  await _waitFor(tester, find.text(home), reason: '$home after force-close + reopen (session restored)');
  expect(find.widgetWithText(ElevatedButton, 'Log in'), findsNothing,
      reason: 'a logged-in user must not be sent back to the login screen after reopening');
}

Future<void> _deleteAccount(WidgetTester tester) async {
  await tester.tap(find.text('Profile').last);
  await _pumpFor(tester, const Duration(seconds: 1));
  final del = find.text('Delete My Account');
  await _reveal(tester, del);
  await tester.tap(del);
  await _waitFor(tester, find.text('Delete Forever'), reason: 'delete-account dialog');

  // Wrong PIN first: the dialog must stay open and show an error.
  await tester.enterText(find.widgetWithText(TextField, 'Current 4-digit PIN'), '0000');
  await _dismissKeyboard(tester);
  await tester.tap(find.text('Delete Forever'));
  // Wait for the server's rejection (slow devices can take a while) rather
  // than a fixed delay: the dialog shows a spinner while the request runs.
  await _waitFor(tester, find.text('Invalid code'), reason: 'wrong-PIN error in the delete dialog');
  expect(find.text('Delete Forever'), findsOneWidget, reason: 'wrong PIN must not delete the account');

  // The field lost focus when the keyboard was dismissed; re-focus it first
  // or enterText is silently ignored and the old (wrong) PIN is resent.
  await tester.tap(find.widgetWithText(TextField, 'Current 4-digit PIN'));
  await _pumpFor(tester, const Duration(milliseconds: 400));
  await tester.enterText(find.widgetWithText(TextField, 'Current 4-digit PIN'), _pin);
  await _dismissKeyboard(tester);
  await tester.tap(find.text('Delete Forever'));
  await _pumpFor(tester, const Duration(milliseconds: 300));
  await _waitFor(tester, find.text('Log in'), reason: 'login screen after account deletion');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Login screen validation and unknown-account error', (tester) async {
    await _launchFresh(tester);

    await _login(tester, phone: '123', pin: _pin);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);

    await _login(tester, phone: '7000990099', pin: '12');
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Enter the 4-digit code'), findsOneWidget);

    // A well-formed phone that has no account anywhere (tries nursenow,
    // then falls back to the caregiver login) must show an error, not hang.
    await _login(tester, phone: '7000990099', pin: _pin);
    await _waitFor(tester, find.textContaining(RegExp('no account|not found|not registered', caseSensitive: false)),
        reason: 'unknown-account error');
  });

  testWidgets('Registration with every field empty highlights errors and does not submit', (tester) async {
    await _launchFresh(tester);
    await tester.tap(find.text('Patient').first);
    await _waitFor(tester, find.widgetWithText(TextField, 'Phone number (Mandatory)'), reason: 'registration form');

    final submit = find.widgetWithText(ElevatedButton, 'Post Requirement');
    await _reveal(tester, submit);
    await tester.tap(submit);
    await _pumpFor(tester, const Duration(seconds: 1));
    // The form scrolls/focuses to the first invalid field; scroll back to
    // the top so the phone/PIN errors are in the built range.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000), warnIfMissed: false);
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(find.text('Enter a 4-digit PIN'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Phone number (Mandatory)'), findsOneWidget,
        reason: 'must still be on the registration form');
  });

  testWidgets('Individual: register+post, tabs, logout, wrong PIN, forgot PIN, cross-role phone clash, delete',
      (tester) async {
    await _launchFresh(tester);

    // --- Register and post the one requirement ---
    await tester.tap(find.text('Patient').first);
    await _waitFor(tester, find.widgetWithText(TextField, 'Phone number (Mandatory)'), reason: 'registration form');
    await _fillIndividualRegistration(tester, phone: _individualPhone);
    final submit = find.widgetWithText(ElevatedButton, 'Post Requirement');
    await _reveal(tester, submit);
    await tester.tap(submit);
    await _waitFor(tester, find.text('Requirement Posted'), reason: 'home after Post Requirement');
    await _waitFor(tester, find.textContaining('Pending admin review'), reason: 'requirement listed as pending');

    // --- Force-close right after registering: still logged in on reopen ---
    await _expectStillLoggedInAfterReopen(tester, 'Requirement Posted');
    await _waitFor(tester, find.textContaining('Pending admin review'), reason: 'requirement still shown after reopen');

    // --- Messages bell (replaced the old Messages tab) opens a bottom sheet ---
    await _waitFor(tester, find.byType(MessagesBellButton), reason: 'messages bell in the app bar');
    await tester.tap(find.byType(MessagesBellButton));
    await _waitFor(tester, find.byType(BottomSheet), reason: 'messages bottom sheet');
    await tester.binding.handlePopRoute(); // system "back" closes the sheet on any screen size
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.byType(BottomSheet), findsNothing, reason: 'messages sheet should be closed');

    // --- Profile tab shows the account ---
    await tester.tap(find.text('Profile').last);
    await _waitFor(tester, find.textContaining(_individualPhone), reason: 'profile shows phone');

    // --- Logout, then wrong PIN is rejected ---
    await _logoutViaLogoTripleTap(tester);

    // --- Logged out: a force-close + reopen must land on the login screen ---
    await _forceCloseAndReopen(tester);
    await _waitFor(tester, find.text('Log in'), reason: 'login screen after reopening while logged out');
    expect(find.text('Requirement Posted'), findsNothing);

    await _login(tester, phone: _individualPhone, pin: '0000');
    await _waitFor(tester, find.textContaining(RegExp('invalid', caseSensitive: false)), reason: 'wrong-PIN error');

    // --- Forgot PIN creates a support ticket and confirms ---
    final forgot = find.text('Forgot PIN?');
    await _reveal(tester, forgot);
    await tester.tap(forgot);
    await _waitFor(tester, find.text('Create Ticket'), reason: 'forgot PIN dialog');
    await tester.tap(find.text('Create Ticket'));
    await _waitFor(tester, find.byType(SnackBar), reason: 'forgot PIN confirmation snackbar');
    await _pumpFor(tester, const Duration(seconds: 1));

    // --- Phone numbers are globally unique: an organisation can't reuse it ---
    await _reveal(tester, find.text('Organisation').first);
    await tester.tap(find.text('Organisation').first);
    await _waitFor(tester, find.text('Contact person name (Mandatory)'), reason: 'org registration form');
    await _fillOrganisationRegistration(tester, phone: _individualPhone);
    final register = find.widgetWithText(ElevatedButton, 'Register');
    await _reveal(tester, register);
    await tester.tap(register);
    await _waitFor(tester, find.textContaining('already registered'), reason: 'AUTH_016 phone clash message');
    await tester.pageBack();
    await _waitFor(tester, find.text('Log in'));

    // --- Correct PIN logs in again, then the account is deleted ---
    await _login(tester, phone: _individualPhone, pin: _pin);
    await _waitFor(tester, find.text('Requirement Posted'), reason: 'home after login');

    // --- A session created by logging in (not just registering) also survives a reopen ---
    await _expectStillLoggedInAfterReopen(tester, 'Requirement Posted');
    await _deleteAccount(tester);

    // The deleted account can no longer log in.
    await _login(tester, phone: _individualPhone, pin: _pin);
    await _waitFor(tester, find.textContaining(RegExp('no account|not found|not registered', caseSensitive: false)),
        reason: 'deleted account rejected');
  });

  testWidgets('Organisation: register, post requirement, menu, logout/login, delete', (tester) async {
    await _launchFresh(tester);

    await tester.tap(find.text('Organisation').first);
    await _waitFor(tester, find.text('Contact person name (Mandatory)'), reason: 'org registration form');
    await _fillOrganisationRegistration(tester, phone: _organisationPhone);
    final register = find.widgetWithText(ElevatedButton, 'Register');
    await _reveal(tester, register);
    await tester.tap(register);
    await _waitFor(tester, find.text('Requirements Posted'), reason: 'org home after registration');

    // --- Force-close right after registering: still logged in on reopen ---
    await _expectStillLoggedInAfterReopen(tester, 'Requirements Posted');

    // --- Post a requirement (stays pending_review: never approved here) ---
    await _waitFor(tester, find.text('Post a Requirement'), reason: 'org home finished loading');
    await tester.tap(find.text('Post a Requirement'));
    await _waitFor(tester, find.widgetWithText(DropdownButtonFormField<String>, 'Type of Nurse/Caregiver (Mandatory)'),
        reason: 'post-requirement form');
    final submitEmpty = find.text('Submit for Review');
    await _reveal(tester, submitEmpty);
    await tester.tap(submitEmpty);
    await _pumpFor(tester, const Duration(milliseconds: 800));
    // The form scrolls to the first invalid field; bring the top back into
    // the built range before asserting.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000), warnIfMissed: false);
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Please select a type'), findsOneWidget, reason: 'empty submit must flag the type');

    await _pickDropdown(tester, 'Type of Nurse/Caregiver (Mandatory)', 'Registered Nurse');
    await _reveal(tester, find.text('Submit for Review'));
    await tester.tap(find.text('Submit for Review'));
    await _waitFor(tester, find.textContaining('Pending admin review'), reason: 'requirement listed as pending');

    // --- Per-requirement menu exposes Edit ---
    await tester.tap(find.byTooltip('More options').first);
    await _waitFor(tester, find.text('Edit the Requirement'), reason: 'requirement menu');
    await tester.tapAt(const Offset(5, 5)); // dismiss the menu
    await _pumpFor(tester, const Duration(milliseconds: 500));

    // --- Profile, logout, login again ---
    await tester.tap(find.text('Profile').last);
    await _waitFor(tester, find.textContaining(_organisationPhone), reason: 'org profile shows phone');
    await _logoutViaLogoTripleTap(tester);
    await _login(tester, phone: _organisationPhone, pin: _pin);
    await _waitFor(tester, find.text('Requirements Posted'), reason: 'org home after login');

    // --- Org session created by logging in also survives a reopen ---
    await _expectStillLoggedInAfterReopen(tester, 'Requirements Posted');

    await _deleteAccount(tester);
  });
}
