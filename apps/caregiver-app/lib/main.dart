import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Configured via android/app/google-services.json — no FirebaseOptions
    // needed on Android. Not configured for web (the Chrome dev target is
    // for UI demos only; push notifications are a mobile-only feature), so
    // this is expected to throw there — caught so the app still starts.
    await Firebase.initializeApp();
  } catch (_) {
    // Best-effort: push notifications just won't work this session.
  }

  // Captured before runApp — on web this reflects the browser's URL/hash
  // (e.g. "/jobs") at load time; on mobile it's always "/". MaterialApp's
  // own fixed initialRoute below would otherwise discard it, so it's
  // threaded through to SplashScreen to restore the page a caregiver was
  // on before a web page refresh instead of always landing on Profile.
  final initialDeepLinkRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final localStorage = await LocalStorage.create();

  runApp(
    ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(localStorage)],
      child: CaregiverApp(initialDeepLinkRoute: initialDeepLinkRoute),
    ),
  );
}
