import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'router.dart';

class NurseNowApp extends StatelessWidget {
  const NurseNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NurseNow',
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
      routes: buildRoutes(),
    );
  }
}
