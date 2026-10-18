import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../shared/widgets/app_shell.dart';
import '../widgets/general_settings_section.dart';
import '../widgets/rate_card_settings_section.dart';
import '../widgets/scope_of_work_settings_section.dart';
import '../widgets/duty_requirements_settings_section.dart';
import '../widgets/app_versions_settings_section.dart';
import '../widgets/maintenance_settings_section.dart';
import '../widgets/login_settings_section.dart';

/// A single consolidated Settings hub — folds what used to be 5 separate
/// sidebar items (Rate Card, Scope of Work, Duty Requirements, App
/// Versions, Login Settings) plus a new "General" tab (the admin-
/// configurable apply-by window, and self-service password change) into
/// one page with a tab strip, replacing those 5 sidebar entries with this
/// single "Settings" one.
///
/// Each tab has its own route (see [tabRoutes]/router.dart) so it's
/// independently bookmarkable/shareable/refresh-stable, same as every
/// other admin-web screen — [initialTabIndex] is what tells this screen
/// which tab to open on, set per-route in router.dart. A deliberate,
/// user-driven tab switch (tapping the TabBar) pushes a replacement route
/// matching the new tab so the browser's address bar follows it; this
/// mirrors how every other sidebar-driven screen transition in this app
/// already works (pushNamedAndRemoveUntil), rather than introducing a new,
/// URL-less way to navigate.
class SettingsScreen extends StatefulWidget {
  final int initialTabIndex;

  const SettingsScreen({super.key, this.initialTabIndex = 0});

  static const _tabs = [
    Tab(icon: Icon(Icons.tune), text: 'General'),
    Tab(icon: Icon(Icons.currency_rupee), text: 'Rate Card'),
    Tab(icon: Icon(Icons.checklist), text: 'Scope of Work'),
    Tab(icon: Icon(Icons.assignment_outlined), text: 'Duty Requirements'),
    Tab(icon: Icon(Icons.system_update), text: 'App Versions'),
    Tab(icon: Icon(Icons.build_circle_outlined), text: 'Maintenance Mode'),
    Tab(icon: Icon(Icons.password), text: 'Login Settings'),
  ];

  /// Index-matched to [_tabs] — the route each tab's own URL resolves to.
  /// Kept in sync with router.dart and root_screen.dart's
  /// _restorableRoutes by hand, same convention as every other static
  /// admin-web route.
  static const tabRoutes = [
    '/settings',
    '/settings/rate-card',
    '/settings/scope-of-work',
    '/settings/duty-requirements',
    '/settings/app-versions',
    '/settings/maintenance',
    '/settings/login',
  ];

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: SettingsScreen._tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _controller.addListener(_onTabChanged);
  }

  // Fires once a tab change (tap or swipe) settles on its final index —
  // TabController's listener fires repeatedly mid-animation, so
  // indexIsChanging gates this to the settled value. Only a genuine
  // user-driven change ever reaches here: the initial index is set via the
  // constructor above, which doesn't trigger this listener (it's attached
  // afterward), so there's no risk of this immediately re-navigating to
  // the route we're already on.
  void _onTabChanged() {
    if (_controller.indexIsChanging) return;
    Navigator.of(context).pushReplacementNamed(SettingsScreen.tabRoutes[_controller.index]);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.settings,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
              child: Text('Settings',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: TabBar(
                controller: _controller,
                isScrollable: true,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: SettingsScreen._tabs,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _controller,
                children: const [
                  GeneralSettingsSection(),
                  RateCardSettingsSection(),
                  ScopeOfWorkSettingsSection(),
                  DutyRequirementsSettingsSection(),
                  AppVersionsSettingsSection(),
                  MaintenanceSettingsSection(),
                  LoginSettingsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
