import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'router.dart';

class CaregiverApp extends StatelessWidget {
  /// The route the browser's URL/hash actually pointed at when the page
  /// loaded (captured in main() before runApp) — threaded down to
  /// SplashScreen so a web page refresh can restore the tab/page the
  /// caregiver was actually on instead of always landing on Profile.
  /// Always "/" on mobile (no browser URL), so a no-op there.
  final String? initialDeepLinkRoute;

  const CaregiverApp({super.key, this.initialDeepLinkRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NurseJobs',
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
    );
  }
}
