import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/network/api_exception.dart';
import '../core/providers.dart';

/// SPEC.md 12: "Show bottom navigation bar at all times after registration
/// (including pending statuses). Seeing jobs motivates caregivers to
/// complete onboarding." Each screen owns its own Scaffold/AppBar and just
/// embeds this as its bottomNavigationBar — switching tabs replaces the
/// current route (not a stack push), matching normal tab-bar semantics.
///
/// The MyJobs tab shows a small red badge with the count of currently
/// active (not yet closed) assignments — jobs AND organisation
/// requirements together, matching the same merge MyAssignmentScreen
/// itself renders. Fetched eagerly on mount, same convention as
/// MessagesBellButton — fails open (badge just stays at 0) on a network
/// error, since this is a passive indicator that must never crash or block
/// the screen it's embedded in.
class CaregiverBottomNav extends ConsumerStatefulWidget {
  final int currentIndex;

  const CaregiverBottomNav({super.key, required this.currentIndex});

  @override
  ConsumerState<CaregiverBottomNav> createState() => _CaregiverBottomNavState();
}

class _CaregiverBottomNavState extends ConsumerState<CaregiverBottomNav> {
  int _activeAssignmentCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // applyByWindowDaysProvider is also set by login_screen.dart/
    // registration_screen.dart's own initState, but those only run for a
    // caregiver who actually passes through sign-in — an already-
    // authenticated caregiver (the common case: caregiver tokens never
    // expire) launches straight into a tab via the host app's own splash
    // screen, which has no knowledge of this caregiver-specific setting at
    // all (see CLAUDE.md's Login Settings/OTP-mode note for the same
    // per-app-fetch gap). CaregiverBottomNav is embedded in all 3 tabs and
    // re-mounts on every tab switch, so fetching here too closes that gap
    // for every real session regardless of how it started — this was
    // previously the (now-removed) unreachable caregiver splash screen's
    // job. Read eagerly alongside the existing assignment-count fetch,
    // same fail-open convention.
    unawaited(
      ref.read(jobSettingsRepositoryProvider).getApplyByWindowDays().then((days) {
        if (mounted) ref.read(applyByWindowDaysProvider.notifier).state = days;
      }),
    );
    try {
      final results = await Future.wait([
        ref.read(jobsRepositoryProvider).getAssignedJobs(),
        ref.read(organisationOpeningsRepositoryProvider).getAssigned(),
      ]);
      final jobs = results[0] as List<JobModel>;
      final requirements = results[1] as List<OrganisationRequirementModel>;
      if (!mounted) return;
      final count = jobs.where((j) => j.myApplication?.status != JobApplicationStatus.completed).length +
          requirements.where((r) => r.myApplication?.status != JobApplicationStatus.completed).length;
      setState(() => _activeAssignmentCount = count);
    } on ApiException {
      // Fails open — a passive badge must never crash or block the bottom
      // nav it's embedded in over a failed fetch.
    }
  }

  @override
  Widget build(BuildContext context) {
    const routes = ['/caregiver/profile', '/caregiver/jobs', '/caregiver/my-jobs'];
    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == widget.currentIndex) return;
        Navigator.of(context).pushReplacementNamed(routes[index]);
      },
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        // Jobs shows both admin/individual jobs AND organisation
        // (hospital/rehab/clinic) requirements together — see JobsScreen.
        const BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
        BottomNavigationBarItem(
          icon: _BadgedIcon(icon: Icons.assignment_ind, count: _activeAssignmentCount),
          label: 'MyJobs',
        ),
      ],
    );
  }
}

/// A bottom-nav icon with a small red count badge pinned to its top-right
/// corner — same visual language as MessagesBellButton's unread badge
/// (red circle, white border, white bold number), just anchored to a
/// BottomNavigationBarItem's icon instead of an AppBar action.
class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _BadgedIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
