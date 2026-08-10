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

  final localStorage = await LocalStorage.create();

  runApp(
    ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(localStorage)],
      child: const CaregiverApp(),
    ),
  );
}
