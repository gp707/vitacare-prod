import 'package:flutter/material.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/registration/screens/registration_screen.dart';
import '../features/registration/screens/pending_call_screen.dart';
import '../features/profile/screens/profile_view_screen.dart';
import '../features/jobs/screens/jobs_screen.dart';
import '../features/jobs/screens/my_assignment_screen.dart';

/// Availability/Home/Jobs/Settings routes are added in later phases as
/// those features land (SPEC.md 12.1). This covers the onboarding funnel:
/// Login/Register (all fields, including documents, are collected on this
/// one screen — no separate "Advanced Details" step) -> Pending Call,
/// landing on the caregiver's own full profile by default for everything
/// after that (reachable at any status, per SPEC.md 12.3) — no extra click
/// needed to see it. Every self-editable field is edited inline, in place,
/// directly on ProfileViewScreen (pencil icon -> edit -> save/cancel) —
/// there is no separate Edit Profile screen/route. There is deliberately no
/// `/caregiver` (bare) entry — that used to map to a caregiver-only splash
/// screen, removed entirely once the merge made it permanently unreachable
/// (nothing ever navigates to the bare prefix; see CLAUDE.md's "Merged into
/// one binary with NurseJobs").
/// All routes prefixed `/caregiver` — this whole route table is merged into
/// the host JustHeal app's single flat route table (see
/// apps/justheal-app/lib/patient_hospital/app/router.dart) rather than owning its own
/// Navigator, so every key here must avoid colliding with the host's own
/// `/`, `/login`, `/register`, `/profile` routes (see CLAUDE.md's NurseNow
/// section, "Merged into one binary with NurseJobs").
Map<String, WidgetBuilder> buildCaregiverRoutes() {
  return {
    '/caregiver/login': (context) => const LoginScreen(),
    '/caregiver/register': (context) => const RegistrationScreen(),
    '/caregiver/pending-call': (context) => const PendingCallScreen(),
    '/caregiver/profile': (context) => const ProfileViewScreen(),
    '/caregiver/jobs': (context) => const JobsScreen(),
    '/caregiver/my-jobs': (context) => const MyAssignmentScreen(),
  };
}
