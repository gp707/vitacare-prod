import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'patient_hospital/app/app.dart';
import 'patient_hospital/core/providers.dart';
import 'patient_hospital/core/storage/local_storage.dart';
import 'caregiver/core/providers.dart' as caregiver;
import 'caregiver/core/storage/local_storage.dart' as caregiver_storage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Configured via android/app/google-services.json (and, once added,
    // ios/Runner/GoogleService-Info.plist) for the in.vitacasahealth.justheal
    // app identity — no FirebaseOptions needed on Android. Not configured
    // for web (the Chrome dev target is for UI demos only; push
    // notifications are a mobile-only feature, same reasoning as the
    // caregiver flow this mirrors), so this is expected to throw there —
    // caught so the app still starts. Needed here (not just inside
    // lib/caregiver/) because the ported caregiver flow's "New Job" FCM
    // push depends on Firebase having been initialized once, app-wide.
    await Firebase.initializeApp();
  } catch (_) {
    // Best-effort: push notifications just won't work this session.
  }

  // Captured before runApp — on web this reflects the browser's URL/hash
  // (e.g. "/home") at load time. MaterialApp's own fixed initialRoute
  // below would otherwise discard it, so it's threaded through to
  // SplashScreen to restore the page the account was on before a web page
  // refresh instead of always landing on their home tab.
  final initialDeepLinkRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final localStorage = await LocalStorage.create();
  // The ported caregiver flow is a second, independent session sharing
  // this one binary (see CLAUDE.md's JustHeal merge notes) — it needs its
  // own LocalStorage override too, not just this app's own, or any
  // caregiver login/session read throws UnimplementedError.
  final caregiverLocalStorage = await caregiver_storage.LocalStorage.create();

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        caregiver.localStorageProvider.overrideWithValue(caregiverLocalStorage),
      ],
      child: NurseNowApp(initialDeepLinkRoute: initialDeepLinkRoute),
    ),
  );
}
