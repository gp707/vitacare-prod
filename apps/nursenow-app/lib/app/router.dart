import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/registration_screen.dart';
import '../features/individual/screens/jobs_posted_screen.dart';
import '../features/individual/screens/post_requirement_screen.dart';
import '../features/individual/screens/profile_screen.dart';
import '../features/organisation/screens/requirements_posted_screen.dart';
import '../features/organisation/screens/post_organisation_requirement_screen.dart';

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
Map<String, WidgetBuilder> buildRoutes() {
  return {
    '/': (context) => const SplashScreen(),
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegistrationScreen(),
    '/home': (context) => const JobsPostedScreen(),
    '/profile': (context) => const ProfileScreen(),
    '/post-requirement': (context) => const PostRequirementScreen(),
    '/org-home': (context) => const RequirementsPostedScreen(),
    '/org-post-requirement': (context) => const PostOrganisationRequirementScreen(),
  };
}
