import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'router.dart';

class AdminWebApp extends StatelessWidget {
  /// The route the browser's URL/hash actually pointed at when the page
  /// loaded (captured in main() before runApp, since MaterialApp's own
  /// fixed initialRoute below would otherwise discard it) — threaded down
  /// to RootScreen so a page refresh can restore the page the admin was
  /// actually on instead of always landing on /dashboard.
  final String? initialDeepLinkRoute;

  const AdminWebApp({super.key, this.initialDeepLinkRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitaCare Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          error: AppColors.error,
        ),
        fontFamily: AppTypography.fontFamily,
      ),
      initialRoute: '/',
      routes: buildRoutes(initialDeepLinkRoute: initialDeepLinkRoute),
      onGenerateRoute: onGenerateRoute,
    );
  }
}
