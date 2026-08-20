import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Captured before runApp — on web this reflects the browser's URL/hash
  // (e.g. "/home") at load time. MaterialApp's own fixed initialRoute
  // below would otherwise discard it, so it's threaded through to
  // SplashScreen to restore the page the account was on before a web page
  // refresh instead of always landing on their home tab.
  final initialDeepLinkRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final localStorage = await LocalStorage.create();

  runApp(
    ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(localStorage)],
      child: NurseNowApp(initialDeepLinkRoute: initialDeepLinkRoute),
    ),
  );
}
