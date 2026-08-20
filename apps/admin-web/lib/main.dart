import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Captured before runApp — MaterialApp below always enters via the fixed
  // initialRoute '/' (RootScreen) so the auth check runs first, which
  // immediately rewrites the browser's URL/hash. Without capturing the
  // real pre-refresh route here first, RootScreen would have no way to
  // know the user was on e.g. "/jobs" before hitting reload — see
  // RootScreen's use of this value.
  final initialDeepLinkRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final localStorage = await LocalStorage.create();

  runApp(
    ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(localStorage)],
      child: AdminWebApp(initialDeepLinkRoute: initialDeepLinkRoute),
    ),
  );
}
