import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/dashboard/data/dashboard_repository.dart';
import 'package:admin_web/shared/state/sidebar_badge_counts_notifier.dart';
import 'package:admin_web/shared/widgets/app_shell.dart';

DashboardStats _stats({
  int pendingCall = 0,
  int jobsPendingApproval = 0,
  int openTicketsCount = 0,
}) {
  return DashboardStats(
    totalCaregivers: 0,
    pendingCall: pendingCall,
    available: 0,
    unavailable: 0,
    assigned: 0,
    rejected: 0,
    pendingEditsCount: 0,
    newRegistrations24h: 0,
    newRegistrations7d: 0,
    jobsPendingApproval: jobsPendingApproval,
    newOrganisations7d: 0,
    newIndividuals7d: 0,
    openTicketsCount: openTicketsCount,
  );
}

Future<void> _pumpShellAs(WidgetTester tester, String role, {DashboardStats? badgeCounts}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: role),
        ),
        if (badgeCounts != null)
          sidebarBadgeCountsProvider.overrideWith(
            (ref) => SidebarBadgeCountsNotifier(DashboardRepository(Dio()))..state = badgeCounts,
          ),
      ],
      child: const MaterialApp(
        home: AppShell(current: AppShellSection.dashboard, child: SizedBox()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows Admin Management for a super_admin session',
      (tester) async {
    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Admin Management'), findsOneWidget);
  });

  testWidgets('hides Admin Management for a regular admin session',
      (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Admin Management'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Caregivers'), findsOneWidget);
  });

  testWidgets('shows Audit Logs for both admin and super_admin sessions',
      (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Audit Logs'), findsOneWidget);

    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Audit Logs'), findsOneWidget);
  });

  testWidgets('shows Patients/Family for both admin and super_admin sessions',
      (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Patients/Family'), findsOneWidget);

    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Patients/Family'), findsOneWidget);
  });

  testWidgets('shows Reports for both admin and super_admin sessions',
      (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Reports'), findsOneWidget);

    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Reports'), findsOneWidget);
  });

  testWidgets('shows Settings for both admin and super_admin sessions',
      (tester) async {
    await _pumpShellAs(tester, 'admin');
    expect(find.text('Settings'), findsOneWidget);

    await _pumpShellAs(tester, 'super_admin');
    expect(find.text('Settings'), findsOneWidget);
  });

  group('sidebar badge counts', () {
    testWidgets(
        'shows a red count badge on Tickets/Jobs/Caregivers reflecting open tickets, pending-approval jobs, and '
        'pending-call caregivers', (tester) async {
      await _pumpShellAs(tester, 'admin',
          badgeCounts: _stats(pendingCall: 3, jobsPendingApproval: 7, openTicketsCount: 2));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows no badge on a count of zero — not an empty/zero pill', (tester) async {
      await _pumpShellAs(tester, 'admin',
          badgeCounts: _stats(pendingCall: 0, jobsPendingApproval: 0, openTicketsCount: 0));

      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows no badge at all while badgeCounts has not loaded yet (null)', (tester) async {
      await _pumpShellAs(tester, 'admin');

      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      // Nothing resembling a badge count should render — spot-check a
      // couple of plausible stray digits.
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('caps the displayed count at "99+" for a pathologically large backlog', (tester) async {
      await _pumpShellAs(tester, 'admin', badgeCounts: _stats(openTicketsCount: 140));

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('140'), findsNothing);
    });
  });
}
