import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../shared/widgets/app_shell.dart';
import '../widgets/general_settings_section.dart';
import '../widgets/rate_card_settings_section.dart';
import '../widgets/scope_of_work_settings_section.dart';
import '../widgets/duty_requirements_settings_section.dart';
import '../widgets/app_versions_settings_section.dart';
import '../widgets/login_settings_section.dart';

/// A single consolidated Settings hub — folds what used to be 5 separate
/// sidebar items (Rate Card, Scope of Work, Duty Requirements, App
/// Versions, Login Settings) plus a new "General" tab (the admin-
/// configurable apply-by window, and self-service password change) into
/// one page with a tab strip, replacing those 5 sidebar entries with this
/// single "Settings" one.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _tabs = [
    Tab(icon: Icon(Icons.tune), text: 'General'),
    Tab(icon: Icon(Icons.currency_rupee), text: 'Rate Card'),
    Tab(icon: Icon(Icons.checklist), text: 'Scope of Work'),
    Tab(icon: Icon(Icons.assignment_outlined), text: 'Duty Requirements'),
    Tab(icon: Icon(Icons.system_update), text: 'App Versions'),
    Tab(icon: Icon(Icons.password), text: 'Login Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.settings,
      child: SafeArea(
        child: DefaultTabController(
          length: _tabs.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
                child: Text('Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: TabBar(
                  isScrollable: true,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: _tabs,
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    GeneralSettingsSection(),
                    RateCardSettingsSection(),
                    ScopeOfWorkSettingsSection(),
                    DutyRequirementsSettingsSection(),
                    AppVersionsSettingsSection(),
                    LoginSettingsSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
