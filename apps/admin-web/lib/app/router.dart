import 'package:flutter/material.dart';
import 'root_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/caregivers/screens/caregiver_list_screen.dart';
import '../features/caregivers/screens/caregiver_detail_screen.dart';
import '../features/admin_management/screens/admin_management_screen.dart';
import '../features/audit_logs/screens/audit_logs_screen.dart';
import '../features/jobs/screens/admin_jobs_screen.dart';
import '../features/app_versions/screens/app_versions_screen.dart';
import '../features/individuals/screens/individuals_list_screen.dart';
import '../features/individuals/screens/individual_detail_screen.dart';
import '../features/organisations/screens/organisations_list_screen.dart';
import '../features/organisations/screens/organisation_detail_screen.dart';
import '../features/reports/screens/reports_screen.dart';

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
    '/app-versions': (context) => const AppVersionsScreen(),
    '/patients-family': (context) => const IndividualsListScreen(),
    '/rehab-hospitals': (context) => const OrganisationsListScreen(),
    '/reports': (context) => const ReportsScreen(),
  };
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/jobs':
      return MaterialPageRoute(
        builder: (context) => AdminJobsScreen(
            initialFilter: settings.arguments as JobsScreenInitialFilter?),
      );
    case '/caregivers':
      return MaterialPageRoute(
        builder: (context) =>
            CaregiverListScreen(initialStatus: settings.arguments as String?),
      );
    case '/caregiver-detail':
      return MaterialPageRoute(
        builder: (context) =>
            CaregiverDetailScreen(profileId: settings.arguments as String),
      );
    case '/audit-logs':
      return MaterialPageRoute(
        builder: (context) =>
            AuditLogsScreen(initialTargetUserId: settings.arguments as String?),
      );
    case '/individual-detail':
      return MaterialPageRoute(
        builder: (context) =>
            IndividualDetailScreen(userId: settings.arguments as String),
      );
    case '/organisation-detail':
      return MaterialPageRoute(
        builder: (context) =>
            OrganisationDetailScreen(userId: settings.arguments as String),
      );
    default:
      return null;
  }
}
