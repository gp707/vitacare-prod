import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_list_screen.dart';

AdminCaregiverListItem _item({
  String userId = 'u1',
  String profileId = 'profile-1',
  int? caregiverNumber = 500,
  String fullName = 'Ramesh Kumar',
  String verificationStatus = 'available',
}) {
  return AdminCaregiverListItem(
    userId: userId,
    profileId: profileId,
    caregiverNumber: caregiverNumber,
    fullName: fullName,
    phone: '+919876543210',
    gender: 'male',
    age: 34,
    highestQualification: 'rn_above_2_years',
    verificationStatus: verificationStatus,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminCaregiversRepository extends AdminCaregiversRepository {
  List<AdminCaregiverListItem> items;
  _FakeAdminCaregiversRepository(this.items) : super(Dio());

  @override
  Future<CaregiverListResult> list(CaregiverListFilters filters) async {
    return CaregiverListResult(
      items: items,
      meta: PaginationMeta(
          page: 1, limit: 20, total: items.length, totalPages: 1),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminCaregiversRepository repo, {
  Size surfaceSize = const Size(1400, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  // Two separate mechanisms: setSurfaceSize controls the actual render/
  // hit-test viewport, while view.physicalSize/devicePixelRatio is what
  // MediaQuery (and this app's isMobile/isCompact breakpoints) reports —
  // both need setting to consistently simulate a given screen width.
  await tester.binding.setSurfaceSize(surfaceSize);
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.view.reset();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminCaregiversRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state =
                AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: CaregiverListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('at desktop width, lists caregivers in a DataTable',
      (tester) async {
    await _pump(tester, _FakeAdminCaregiversRepository([_item()]));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('NUR-500'), findsOneWidget);
  });

  testWidgets(
      'below the mobile breakpoint, shows a stacked card per caregiver instead of a DataTable',
      (tester) async {
    await _pump(tester, _FakeAdminCaregiversRepository([_item()]),
        surfaceSize: const Size(390, 800));

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.textContaining('NUR-500'), findsOneWidget);
  });

  testWidgets(
      'tapping a caregiver card navigates to /caregiver-detail with the profile id',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.reset();
    });
    final repo = _FakeAdminCaregiversRepository([_item()]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          adminCaregiversRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state =
                  AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
        ],
        child: MaterialApp(
          home: const CaregiverListScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Text('Caregiver Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ramesh Kumar'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/caregiver-detail');
    expect(pushedArgs, 'profile-1');
  });
}
