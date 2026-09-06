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
import 'package:admin_web/features/dashboard/screens/dashboard_screen.dart';
import 'package:admin_web/features/jobs/screens/admin_jobs_screen.dart';

DashboardStats _stats({
  int jobsPendingApproval = 4,
  int newOrganisations7d = 2,
  int newIndividuals7d = 6,
}) {
  return DashboardStats(
    totalCaregivers: 100,
    pendingCall: 10,
    available: 60,
    unavailable: 5,
    assigned: 20,
    rejected: 5,
    pendingEditsCount: 3,
    newRegistrations24h: 1,
    newRegistrations7d: 8,
    jobsPendingApproval: jobsPendingApproval,
    newOrganisations7d: newOrganisations7d,
    newIndividuals7d: newIndividuals7d,
  );
}

class _FakeDashboardRepository extends DashboardRepository {
  final DashboardStats stats;
  _FakeDashboardRepository(this.stats) : super(Dio());

  @override
  Future<DashboardStats> getStats() async => stats;
}

Future<void> _pump(
  WidgetTester tester,
  DashboardStats stats, {
  void Function(String? route, Object? args)? onPush,
}) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository(stats)),
      ],
      child: MaterialApp(
        home: const DashboardScreen(),
        onGenerateRoute: (settings) {
          onPush?.call(settings.name, settings.arguments);
          return MaterialPageRoute(
            builder: (_) => Scaffold(body: Text('Route: ${settings.name}')),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Needs Approval, New Organisations (7d), and New Patients (7d) tiles with their counts',
      (tester) async {
    await _pump(tester, _stats(jobsPendingApproval: 4, newOrganisations7d: 2, newIndividuals7d: 6));

    expect(find.text('Needs Approval'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('New Organisations (7d)'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('New Patients (7d)'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('tapping Needs Approval navigates to /jobs pre-filtered to pending_review', (tester) async {
    String? pushedRoute;
    Object? pushedArgs;
    await _pump(
      tester,
      _stats(),
      onPush: (route, args) {
        pushedRoute = route;
        pushedArgs = args;
      },
    );

    await tester.tap(find.text('Needs Approval'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/jobs');
    final filter = pushedArgs as JobsScreenInitialFilter;
    expect(filter.status, 'pending_review');
    expect(filter.postedByUserId, isNull);
  });

  testWidgets('tapping New Organisations (7d) navigates to /rehab-hospitals', (tester) async {
    String? pushedRoute;
    await _pump(tester, _stats(), onPush: (route, _) => pushedRoute = route);

    await tester.tap(find.text('New Organisations (7d)'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/rehab-hospitals');
  });

  testWidgets('tapping New Patients (7d) navigates to /patients-family', (tester) async {
    String? pushedRoute;
    await _pump(tester, _stats(), onPush: (route, _) => pushedRoute = route);

    await tester.tap(find.text('New Patients (7d)'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/patients-family');
  });
}
