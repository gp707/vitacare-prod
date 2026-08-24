import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../features/auth/state/session_notifier.dart';
import '../../features/auth/state/session_state.dart';

enum AppShellSection {
  dashboard,
  caregivers,
  patientsFamily,
  jobs,
  rehabHospitals,
  reports,
  auditLogs,
  adminManagement,
  appVersions,
  loginSettings,
}

/// Nav shell used by every authenticated screen. Below the tablet
/// breakpoint (see [ResponsiveContext.isCompact]) the permanent 220px
/// sidebar doesn't fit comfortably alongside real content, so it collapses
/// into an [AppBar] + [Drawer] instead — same [_NavList] either way, just a
/// different container around it.
/// SPEC.md 13.2: Dashboard / Caregivers / Audit Logs (admin + super_admin) /
/// Admin Management (super-admin only) — Settings is out of scope for this phase.
class AppShell extends ConsumerWidget {
  final AppShellSection current;
  final Widget child;

  const AppShell({super.key, required this.current, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isSuperAdmin =
        session is AdminSessionAuthenticated && session.isSuperAdmin;

    if (context.isCompact) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 1,
          title: const Text(
            'VitaCare Admin',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
          ),
        ),
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: SafeArea(
              child: _NavList(
                  current: current, isSuperAdmin: isSuperAdmin, ref: ref)),
        ),
        body: child,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          Container(
            width: 220,
            color: AppColors.surface,
            child: _NavList(
                current: current, isSuperAdmin: isSuperAdmin, ref: ref),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The nav items themselves — shared verbatim between the permanent
/// sidebar (desktop/tablet) and the [Drawer] (mobile/compact tablet).
class _NavList extends StatelessWidget {
  final AppShellSection current;
  final bool isSuperAdmin;
  final WidgetRef ref;

  const _NavList(
      {required this.current, required this.isSuperAdmin, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nav items scroll independently of the pinned Logout below — the
        // sidebar's item count has grown over time (and will keep
        // growing), so a fixed-height Column would eventually overflow on
        // short screens instead of just scrolling.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'VitaCare Admin',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _NavItem(
                  icon: Icons.grid_view,
                  label: 'Dashboard',
                  selected: current == AppShellSection.dashboard,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/dashboard', (r) => false),
                ),
                _NavItem(
                  icon: Icons.people,
                  label: 'Caregivers',
                  selected: current == AppShellSection.caregivers,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/caregivers', (r) => false),
                ),
                _NavItem(
                  icon: Icons.family_restroom,
                  label: 'Patients/Family',
                  selected: current == AppShellSection.patientsFamily,
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/patients-family', (r) => false),
                ),
                _NavItem(
                  icon: Icons.work,
                  label: 'Jobs',
                  selected: current == AppShellSection.jobs,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/jobs', (r) => false),
                ),
                _NavItem(
                  icon: Icons.local_hospital,
                  label: 'Rehab/Hospitals',
                  selected: current == AppShellSection.rehabHospitals,
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/rehab-hospitals', (r) => false),
                ),
                _NavItem(
                  icon: Icons.query_stats,
                  label: 'Reports',
                  selected: current == AppShellSection.reports,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/reports', (r) => false),
                ),
                _NavItem(
                  icon: Icons.history,
                  label: 'Audit Logs',
                  selected: current == AppShellSection.auditLogs,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/audit-logs', (r) => false),
                ),
                if (isSuperAdmin)
                  _NavItem(
                    icon: Icons.shield,
                    label: 'Admin Management',
                    selected: current == AppShellSection.adminManagement,
                    onTap: () => Navigator.of(context)
                        .pushNamedAndRemoveUntil('/admins', (r) => false),
                  ),
                _NavItem(
                  icon: Icons.system_update,
                  label: 'App Versions',
                  selected: current == AppShellSection.appVersions,
                  onTap: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/app-versions', (r) => false),
                ),
                _NavItem(
                  icon: Icons.password,
                  label: 'Login Settings',
                  selected: current == AppShellSection.loginSettings,
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login-settings', (r) => false),
                ),
              ],
            ),
          ),
        ),
        _NavItem(
          icon: Icons.logout,
          label: 'Logout',
          selected: false,
          onTap: () async {
            final navigator = Navigator.of(context);
            await ref.read(sessionProvider.notifier).logout();
            navigator.pushNamedAndRemoveUntil('/login', (r) => false);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      child: ListTile(
        leading: Icon(icon,
            color: selected ? AppColors.primary : AppColors.textSecondary),
        title: Text(
          label,
          style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textPrimary),
        ),
        onTap: onTap,
      ),
    );
  }
}
