import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// Mirrors NurseJobs (caregiver-app)'s CaregiverBottomNav pattern — each
/// screen owns its own Scaffold/AppBar and just embeds this as its
/// bottomNavigationBar. Profile (identity + phone/PIN self-edit, same
/// route for both account types — ProfileScreen branches internally) and
/// the requirement history + post entry point — a different route per
/// account type (JobsPostedScreen for Individual, RequirementsPostedScreen
/// for Organisation), since the two have genuinely different data models
/// and application-review UX (see "NurseNow" in CLAUDE.md) — are shared by
/// both account types, so both are just 2 tabs now. **Individual's status-
/// based tips (see requirement_messages.dart) no longer have their own
/// dedicated Messages tab** — they moved into MessagesBellButton
/// (app/messages_bell.dart), a swinging bell + unread badge shown in the
/// AppBar of every Individual-only screen, opening an overlay on tap
/// instead of navigating to a separate page.
class NurseNowBottomNav extends ConsumerWidget {
  final int currentIndex;

  const NurseNowBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isOrganisation = session is SessionAuthenticated && session.isOrganisation;
    final routes = isOrganisation ? ['/profile', '/org-home'] : ['/profile', '/home'];
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == currentIndex) return;
        Navigator.of(context).pushReplacementNamed(routes[index]);
      },
      items: isOrganisation
          ? const [
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
              BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Requirements'),
            ]
          : const [
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
              BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Requirement Posted'),
            ],
    );
  }
}
