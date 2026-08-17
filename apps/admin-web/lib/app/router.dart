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

/// Settings route is added in a later phase (SPEC.md 13.1).
/// /caregivers accepts an optional status filter, /caregiver-detail a
/// profile id, and /audit-logs an optional target-user-id prefilter, all
/// passed as route arguments (see onGenerateRoute) rather than path
/// segments, to keep routing simple with MaterialApp's basic named-route
/// table.
Map<String, WidgetBuilder> buildRoutes() {
  return {
    '/': (context) => const RootScreen(),
    '/login': (context) => const LoginScreen(),
    '/dashboard': (context) => const DashboardScreen(),
    '/admins': (context) => const AdminManagementScreen(),
    '/jobs': (context) => const AdminJobsScreen(),
    '/app-versions': (context) => const AppVersionsScreen(),
  };
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/caregivers':
      return MaterialPageRoute(
        builder: (context) => CaregiverListScreen(initialStatus: settings.arguments as String?),
      );
    case '/caregiver-detail':
      return MaterialPageRoute(
        builder: (context) => CaregiverDetailScreen(profileId: settings.arguments as String),
      );
    case '/audit-logs':
      return MaterialPageRoute(
        builder: (context) => AuditLogsScreen(initialTargetUserId: settings.arguments as String?),
      );
    default:
      return null;
  }
}
