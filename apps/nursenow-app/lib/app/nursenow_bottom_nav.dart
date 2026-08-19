import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// Mirrors NurseJobs (caregiver-app)'s CaregiverBottomNav pattern — each
/// screen owns its own Scaffold/AppBar and just embeds this as its
/// bottomNavigationBar. Two tabs: Profile (identity + phone/PIN self-edit,
/// same route for both account types — ProfileScreen branches internally)
/// and the requirement history + post entry point — a different route per
/// account type (JobsPostedScreen for Individual, RequirementsPostedScreen
/// for Organisation), since the two have genuinely different data models
/// and application-review UX (see "NurseNow" in CLAUDE.md).
class NurseNowBottomNav extends ConsumerWidget {
  final int currentIndex;

  const NurseNowBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isOrganisation = session is SessionAuthenticated && session.isOrganisation;
    final routes = ['/profile', isOrganisation ? '/org-home' : '/home'];
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == currentIndex) return;
        Navigator.of(context).pushReplacementNamed(routes[index]);
      },
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(
          icon: const Icon(Icons.work),
          label: isOrganisation ? 'Requirements' : 'Jobs Posted',
        ),
      ],
    );
  }
}
