import 'package:flutter/material.dart';
import 'root_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/caregivers/screens/caregiver_list_screen.dart';
import '../features/caregivers/screens/caregiver_detail_screen.dart';
import '../features/admin_management/screens/admin_management_screen.dart';
import '../features/audit_logs/screens/audit_logs_screen.dart';
import '../features/jobs/screens/admin_jobs_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/individuals/screens/individuals_list_screen.dart';
import '../features/individuals/screens/individual_detail_screen.dart';
import '../features/organisations/screens/organisations_list_screen.dart';
import '../features/organisations/screens/organisation_detail_screen.dart';
import '../features/reports/screens/reports_screen.dart';
import '../features/individual_messages/screens/individual_messages_screen.dart';
import '../features/caregiver_messages/screens/caregiver_messages_screen.dart';
import '../features/push_notifications/screens/push_notifications_screen.dart';
import '../features/tickets/screens/tickets_screen.dart';
import '../features/error_logs/screens/error_logs_screen.dart';
import '../features/insights/screens/insights_screen.dart';

/// Settings route is added in a later phase (SPEC.md 13.1).
/// /caregivers accepts an optional status filter, /jobs an optional
/// JobsScreenInitialFilter (the "View Jobs" redirect from a single
/// Rehab/Hospitals or Patients/Family row), /caregiver-detail a profile id,
/// /audit-logs an optional target-user-id prefilter, /individual-detail and
/// /organisation-detail a user id, all passed as route arguments (see
/// onGenerateRoute) rather than path segments, to keep routing simple with
/// MaterialApp's basic named-route table.
Map<String, WidgetBuilder> buildRoutes({String? initialDeepLinkRoute}) {
  return {
    '/': (context) => RootScreen(initialDeepLinkRoute: initialDeepLinkRoute),
    '/login': (context) => const LoginScreen(),
    '/dashboard': (context) => const DashboardScreen(),
    '/admins': (context) => const AdminManagementScreen(),
    '/settings': (context) => const SettingsScreen(),
    '/settings/rate-card': (context) =>
        const SettingsScreen(initialTabIndex: 1),
    '/settings/scope-of-work': (context) =>
        const SettingsScreen(initialTabIndex: 2),
    '/settings/duty-requirements': (context) =>
        const SettingsScreen(initialTabIndex: 3),
    '/settings/app-versions': (context) =>
        const SettingsScreen(initialTabIndex: 4),
    '/settings/maintenance': (context) =>
        const SettingsScreen(initialTabIndex: 5),
    '/settings/login': (context) => const SettingsScreen(initialTabIndex: 6),
    '/patients-family': (context) => const IndividualsListScreen(),
    '/rehab-hospitals': (context) => const OrganisationsListScreen(),
    '/nursenow-messages': (context) => const IndividualMessagesScreen(),
    '/nursejobs-messages': (context) => const CaregiverMessagesScreen(),
    '/reports': (context) => const ReportsScreen(),
    '/push-notifications': (context) => const PushNotificationsScreen(),
    '/tickets': (context) => const TicketsScreen(),
    '/error-logs': (context) => const ErrorLogsScreen(),
    '/insights': (context) => const InsightsScreen(),
  };
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  // Bookmarkable detail URLs: /jobs/<id> and /requirements/<id> open the
  // Jobs screen with that item's detail dialog already showing. The screen's
  // own route is still named '/jobs' so closing the dialog leaves the URL at
  // the list.
  final name = settings.name ?? '';
  if (name.startsWith('/jobs/') && name.length > '/jobs/'.length) {
    final id = name.substring('/jobs/'.length);
    return MaterialPageRoute(
      settings: const RouteSettings(name: '/jobs'),
      builder: (context) => AdminJobsScreen(openJobId: id),
    );
  }
  if (name.startsWith('/requirements/') &&
      name.length > '/requirements/'.length) {
    final id = name.substring('/requirements/'.length);
    return MaterialPageRoute(
      settings: const RouteSettings(name: '/jobs'),
      builder: (context) => AdminJobsScreen(openRequirementId: id),
    );
  }
  if (name.startsWith('/caregivers/') && name.length > '/caregivers/'.length) {
    final id = name.substring('/caregivers/'.length);
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => CaregiverDetailScreen(profileId: id),
    );
  }
  if (name.startsWith('/patients-family/') &&
      name.length > '/patients-family/'.length) {
    final id = name.substring('/patients-family/'.length);
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => IndividualDetailScreen(userId: id),
    );
  }
  if (name.startsWith('/rehab-hospitals/') &&
      name.length > '/rehab-hospitals/'.length) {
    final id = name.substring('/rehab-hospitals/'.length);
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => OrganisationDetailScreen(userId: id),
    );
  }
  switch (settings.name) {
    case '/jobs':
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => AdminJobsScreen(
            initialFilter: settings.arguments as JobsScreenInitialFilter?),
      );
    case '/caregivers':
      return MaterialPageRoute(
        settings: settings,
        builder: (context) =>
            CaregiverListScreen(initialStatus: settings.arguments as String?),
      );
    case '/caregiver-detail':
      // Existing callers push this name with the profile id as an argument;
      // naming the route /caregivers/<id> is what gives the page its own
      // bookmarkable URL (also handled directly above for a pasted link).
      final profileId = settings.arguments as String;
      return MaterialPageRoute(
        settings:
            RouteSettings(name: '/caregivers/$profileId', arguments: profileId),
        builder: (context) => CaregiverDetailScreen(profileId: profileId),
      );
    case '/audit-logs':
      final args = settings.arguments;
      return MaterialPageRoute(
        settings: settings,
        builder: (context) => args is AuditLogsRouteArgs
            ? AuditLogsScreen(
                initialTargetUserId: args.targetUserId,
                initialJobId: args.jobId,
                initialRequirementId: args.requirementId,
              )
            : AuditLogsScreen(initialTargetUserId: args as String?),
      );
    case '/individual-detail':
      final individualId = settings.arguments as String;
      return MaterialPageRoute(
        settings: RouteSettings(
            name: '/patients-family/$individualId', arguments: individualId),
        builder: (context) => IndividualDetailScreen(userId: individualId),
      );
    case '/organisation-detail':
      final organisationId = settings.arguments as String;
      return MaterialPageRoute(
        settings: RouteSettings(
            name: '/rehab-hospitals/$organisationId',
            arguments: organisationId),
        builder: (context) => OrganisationDetailScreen(userId: organisationId),
      );
    default:
      return null;
  }
}
