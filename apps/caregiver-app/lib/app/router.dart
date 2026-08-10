import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/registration/screens/registration_screen.dart';
import '../features/registration/screens/pending_call_screen.dart';
import '../features/profile/screens/advanced_details_screen.dart';
import '../features/profile/screens/profile_view_screen.dart';
import '../features/profile/screens/edit_basic_profile_screen.dart';
import '../features/profile/screens/edit_advanced_profile_screen.dart';
import '../features/jobs/screens/jobs_screen.dart';

/// Availability/Home/Jobs/Settings routes are added in later phases as
/// those features land (SPEC.md 12.1). This covers the onboarding funnel:
/// Splash -> Login/Register -> Pending Call -> Advanced Details (documents
/// are uploaded inline on this same screen, no separate route), landing on
/// the caregiver's own full profile view/edit by default for everything
/// after that (reachable at any status, per SPEC.md 12.3) — no extra click
/// needed to see it.
Map<String, WidgetBuilder> buildRoutes() {
  return {
    '/': (context) => const SplashScreen(),
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegistrationScreen(),
    '/pending-call': (context) => const PendingCallScreen(),
    '/advanced-details': (context) => const AdvancedDetailsScreen(),
    '/profile': (context) => const ProfileViewScreen(),
    '/profile/edit-basic': (context) => const EditBasicProfileScreen(),
    '/profile/edit-advanced': (context) => const EditAdvancedProfileScreen(),
    '/jobs': (context) => const JobsScreen(),
  };
}
