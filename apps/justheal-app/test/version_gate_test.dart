import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/core/fcm/fcm_service.dart' as cg_fcm;
import 'package:nursenow_app/caregiver/core/storage/local_storage.dart' as cg_storage;
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart' as cg;
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart' as cg_state;
import 'package:nursenow_app/caregiver/features/profile/data/profile_repository.dart' as cg_profile;
import 'package:nursenow_app/patient_hospital/app/version_gate.dart';
import 'package:nursenow_app/patient_hospital/core/fcm/fcm_service.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/core/version/app_version_repository.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_state.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/data/organisation_repository.dart';

class _FakeVersionRepo extends AppVersionRepository {
  final String name;
  final List<String> log;
  UpdateRequiredInfo? answer;
  Completer<UpdateRequiredInfo?>? pending;

  _FakeVersionRepo(this.name, this.log, {this.answer}) : super(Dio());

  @override
  Future<UpdateRequiredInfo?> checkForUpdate() {
    log.add(name);
    return pending != null ? pending!.future : Future.value(answer);
  }
}

const _info = UpdateRequiredInfo(storeUrl: 'https://play.google.com/store/apps/details?id=x', message: 'Please update JustHeal to continue.');

SessionAuthenticated _hostAuthed({String role = 'individual'}) => SessionAuthenticated(
      role: role,
      fullName: 'Asha',
      phone: '+919876543210',
      isJobPostingBlocked: false,
    );

cg_state.SessionAuthenticated _cgAuthed({String status = 'available'}) => cg_state.SessionAuthenticated(
      fullName: 'Nurse One',
      phone: '+919876543211',
      verificationStatus: status,
      hasRequiredDocuments: true,
    );

void main() {
  late SessionNotifier host;
  late cg.SessionNotifier caregiver;
  late List<String> log;
  late _FakeVersionRepo hostRepo;
  late _FakeVersionRepo caregiverRepo;
  var taps = 0;

  Future<void> pump(WidgetTester tester) async {
    taps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => host),
          cg.sessionProvider.overrideWith((ref) => caregiver),
          appVersionRepositoryProvider.overrideWithValue(hostRepo),
          caregiverAppVersionRepositoryProvider.overrideWithValue(caregiverRepo),
        ],
        child: MaterialApp(
          builder: (context, child) => VersionGate(launcher: (_) async => true, child: child!),
          home: Scaffold(body: Center(child: ElevatedButton(onPressed: () => taps++, child: const Text('App button')))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final hostStorage = await LocalStorage.create();
    final cgStorage = await cg_storage.LocalStorage.create();
    host = SessionNotifier(
      hostStorage,
      IndividualRepository(Dio()),
      OrganisationRepository(Dio()),
      FcmService(IndividualRepository(Dio()), OrganisationRepository(Dio())),
    )..state = const SessionUnauthenticated();
    caregiver = cg.SessionNotifier(
      cgStorage,
      cg_profile.ProfileRepository(Dio()),
      cg_fcm.FcmService(cg_profile.ProfileRepository(Dio())),
    )..state = const cg_state.SessionUnauthenticated();
    log = [];
    hostRepo = _FakeVersionRepo('host', log);
    caregiverRepo = _FakeVersionRepo('caregiver', log);
  });

  testWidgets('nothing is checked, and nothing is shown, while nobody is signed in', (tester) async {
    await pump(tester);
    expect(log, isEmpty);
    expect(find.text('Update Required'), findsNothing);
    await tester.tap(find.text('App button'));
    expect(taps, 1);
  });

  testWidgets('a patient/organisation signing in is checked through the host API client', (tester) async {
    hostRepo.answer = null;
    await pump(tester);
    host.state = _hostAuthed();
    await tester.pumpAndSettle();
    expect(log, ['host']);
    expect(find.text('Update Required'), findsNothing);
  });

  testWidgets('when that account is bound by a forced version, the update screen covers the whole app and cannot be tapped through', (tester) async {
    hostRepo.answer = _info;
    await pump(tester);
    host.state = _hostAuthed();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('version-gate-update-required')), findsOneWidget);
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Please update JustHeal to continue.'), findsOneWidget);
    // the app underneath is still there, but unreachable
    await tester.tap(find.text('App button'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('a caregiver signing in is checked through the CAREGIVER API client, not the host one', (tester) async {
    caregiverRepo.answer = _info;
    await pump(tester);
    caregiver.state = _cgAuthed();
    await tester.pumpAndSettle();
    expect(log, ['caregiver']);
    expect(find.text('Update Required'), findsOneWidget);
  });

  testWidgets('a restored session (loading -> signed in) is checked too, so being logged out at launch is no way round', (tester) async {
    host.state = const SessionLoading();
    hostRepo.answer = _info;
    await pump(tester);
    expect(log, isEmpty);
    host.state = _hostAuthed(role: 'organisation');
    await tester.pumpAndSettle();
    expect(log, ['host']);
    expect(find.text('Update Required'), findsOneWidget);
  });

  testWidgets('a status refresh while already signed in does not check again', (tester) async {
    await pump(tester);
    caregiver.state = _cgAuthed(status: 'pending_call');
    await tester.pumpAndSettle();
    caregiver.state = _cgAuthed(status: 'available'); // e.g. the 20-second status poll
    await tester.pumpAndSettle();
    expect(log, ['caregiver']);
  });

  testWidgets('signing out and in again checks again', (tester) async {
    await pump(tester);
    host.state = _hostAuthed();
    await tester.pumpAndSettle();
    host.state = const SessionUnauthenticated();
    await tester.pumpAndSettle();
    host.state = _hostAuthed();
    await tester.pumpAndSettle();
    expect(log, ['host', 'host']);
  });

  testWidgets('fails open: when the check finds nothing (or fails), the app is not blocked', (tester) async {
    hostRepo.answer = null; // what the repository returns on any error
    await pump(tester);
    host.state = _hostAuthed();
    await tester.pumpAndSettle();
    expect(find.text('Update Required'), findsNothing);
    await tester.tap(find.text('App button'));
    expect(taps, 1);
  });

  testWidgets('only the newest answer counts: a slow reply for an earlier sign-in cannot block a later one', (tester) async {
    hostRepo.pending = Completer<UpdateRequiredInfo?>();
    await pump(tester);
    host.state = _hostAuthed(); // first sign-in: reply still pending
    await tester.pump();
    host.state = const SessionUnauthenticated();
    await tester.pump();
    final second = Completer<UpdateRequiredInfo?>();
    hostRepo.pending = second;
    host.state = _hostAuthed(); // second sign-in
    await tester.pump();
    second.complete(null); // the newer one says: no update needed
    await tester.pumpAndSettle();
    expect(log, ['host', 'host']);
    expect(find.text('Update Required'), findsNothing);
  });
}
