import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/registration/screens/registration_screen.dart';
import '../features/registration/screens/pending_call_screen.dart';
import '../features/profile/screens/profile_view_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../features/jobs/screens/jobs_screen.dart';
import '../features/jobs/screens/my_assignment_screen.dart';
import '../features/organisation_openings/screens/organisation_openings_screen.dart';

/// Availability/Home/Jobs/Settings routes are added in later phases as
/// those features land (SPEC.md 12.1). This covers the onboarding funnel:
/// Splash -> Login/Register (all fields, including documents, are collected
/// on this one screen — no separate "Advanced Details" step) -> Pending
/// Call, landing on the caregiver's own full profile view/edit by default
/// for everything after that (reachable at any status, per SPEC.md 12.3) —
/// no extra click needed to see it.
Map<String, WidgetBuilder> buildRoutes() {
  return {
    '/': (context) => const SplashScreen(),
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegistrationScreen(),
    '/pending-call': (context) => const PendingCallScreen(),
    '/profile': (context) => const ProfileViewScreen(),
    '/profile/edit': (context) => const EditProfileScreen(),
    '/jobs': (context) => const JobsScreen(),
    '/my-jobs': (context) => const MyAssignmentScreen(),
    '/organisation-openings': (context) => const OrganisationOpeningsScreen(),
  };
}
