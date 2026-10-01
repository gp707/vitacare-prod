import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/registration_screen.dart';
import '../features/individual/screens/jobs_posted_screen.dart';
import '../features/individual/screens/post_requirement_screen.dart';
import '../features/individual/screens/profile_screen.dart';
import '../features/organisation/screens/requirements_posted_screen.dart';
import '../features/organisation/screens/post_organisation_requirement_screen.dart';
import '../caregiver/app/router.dart' show buildCaregiverRoutes;

/// Two account types, one app: Individual and Organisation both log in
/// through the same Splash/Login/Register flow, but land on a different
/// "home" tab post-auth (SessionAuthenticated.homeRoute decides which) —
/// /home (JobsPostedScreen) for Individual, /org-home
/// (RequirementsPostedScreen) for Organisation. /profile is shared (
/// ProfileScreen branches internally on session.isOrganisation). No
/// status-gated routing like the caregiver app's `verification_status` —
/// neither account type has a verification pipeline, just the two
/// independent block levers described in the NurseNow section of
/// CLAUDE.md.
///
/// Merged with the caregiver flow's own route table (see CLAUDE.md's
/// "Merged into one binary with NurseJobs") — every caregiver route is
/// prefixed `/caregiver/...` by buildCaregiverRoutes() itself, so there's
/// no collision with this table's own `/`, `/login`, `/register`,
/// `/profile`. One flat Map, one MaterialApp, one Navigator for the whole
/// app — not a nested Navigator per flow.
Map<String, WidgetBuilder> buildRoutes({String? initialDeepLinkRoute}) {
  return {
    '/': (context) => SplashScreen(initialDeepLinkRoute: initialDeepLinkRoute),
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegistrationScreen(),
    '/home': (context) => const JobsPostedScreen(),
    '/profile': (context) => const ProfileScreen(),
    '/post-requirement': (context) => const PostRequirementScreen(),
    '/org-home': (context) => const RequirementsPostedScreen(),
    '/org-post-requirement': (context) => const PostOrganisationRequirementScreen(),
    ...buildCaregiverRoutes(initialDeepLinkRoute: initialDeepLinkRoute),
  };
}
