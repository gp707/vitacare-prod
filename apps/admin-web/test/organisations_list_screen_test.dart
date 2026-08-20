import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/jobs/screens/admin_jobs_screen.dart';
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';
import 'package:admin_web/features/organisations/screens/organisations_list_screen.dart';

AdminOrganisationListItem _item({
  String userId = 'u1',
  int? orgNumber = 500,
  String fullName = 'Dr. Rao',
  String organisationName = 'City Rehab Center',
  String organisationType = OrganisationType.hospital,
  bool isActive = true,
  bool isJobPostingBlocked = false,
  String? blockReason,
}) {
  return AdminOrganisationListItem(
    userId: userId,
    orgNumber: orgNumber,
    fullName: fullName,
    phone: '+919876543210',
    organisationName: organisationName,
    organisationType: organisationType,
    city: City.bangalore,
    area: 'Whitefield',
    isActive: isActive,
    isJobPostingBlocked: isJobPostingBlocked,
    blockReason: blockReason,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminOrganisationsRepository extends AdminOrganisationsRepository {
  List<AdminOrganisationListItem> items;
  String? blockedUserId;
  String? blockedLevel;
  String? blockedReason;
  String? unblockedUserId;
  String? unblockedLevel;
  OrganisationListFilters? lastFilters;

  _FakeAdminOrganisationsRepository(this.items) : super(Dio());

  @override
  Future<AdminOrganisationsListResult> list({
    int page = 1,
    int limit = 20,
    OrganisationListFilters filters = const OrganisationListFilters(),
  }) async {
    lastFilters = filters;
    return AdminOrganisationsListResult(
      items: items,
      meta: PaginationMeta(page: page, limit: limit, total: items.length, totalPages: 1),
    );
  }

  @override
  Future<void> block(String userId, String level, String reason) async {
    blockedUserId = userId;
    blockedLevel = level;
    blockedReason = reason;
  }

  @override
  Future<void> unblock(String userId, String level) async {
    unblockedUserId = userId;
    unblockedLevel = level;
  }
}

Future<void> _selectFilterDropdown(WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field = find.widgetWithText(DropdownButtonFormField<String?>, fieldLabel).first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, _FakeAdminOrganisationsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(2300, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminOrganisationsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: OrganisationsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists organisation accounts with their status and location', (tester) async {
    await _pump(tester, _FakeAdminOrganisationsRepository([_item()]));

    expect(find.text('City Rehab Center'), findsOneWidget);
    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Bangalore, Whitefield'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('ORG-500'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no organisations', (tester) async {
    await _pump(tester, _FakeAdminOrganisationsRepository([]));

    expect(find.text('No organisation accounts yet.'), findsOneWidget);
  });

  testWidgets('shows the block reason for a job-posting-blocked account', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationsRepository([
        _item(isJobPostingBlocked: true, blockReason: 'Suspicious activity'),
      ]),
    );

    expect(find.text('Posting blocked: Suspicious activity'), findsOneWidget);
    expect(find.text('Unblock Posting'), findsOneWidget);
  });

  testWidgets('shows Blocked for a fully-blocked (inactive) account', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationsRepository([_item(isActive: false, blockReason: 'Fraudulent postings')]),
    );

    expect(find.text('Blocked: Fraudulent postings'), findsOneWidget);
    expect(find.text('Unblock'), findsOneWidget);
  });

  testWidgets('blocking job posting opens a reason dialog and calls the repository', (tester) async {
    final repo = _FakeAdminOrganisationsRepository([_item()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Block Posting'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Suspicious activity');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(repo.blockedUserId, 'u1');
    expect(repo.blockedLevel, 'job_posting');
    expect(repo.blockedReason, 'Suspicious activity');
  });

  testWidgets('unblocking a fully-blocked account calls the repository with level=full', (tester) async {
    final repo = _FakeAdminOrganisationsRepository([_item(isActive: false)]);
    await _pump(tester, repo);

    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Unblock')).onPressed!();
    await tester.pumpAndSettle();

    expect(repo.unblockedUserId, 'u1');
    expect(repo.unblockedLevel, 'full');
  });

  testWidgets('entering a search term and picking an organisation type/city, then Apply Filters, passes them through',
      (tester) async {
    final repo = _FakeAdminOrganisationsRepository([_item()]);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search name, phone, or ID (ORG-...)'),
      'ORG-500',
    );
    await _selectFilterDropdown(tester, 'Organisation Type', 'Hospital');
    await _selectFilterDropdown(tester, 'City', 'Bangalore');
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, 'ORG-500');
    expect(repo.lastFilters?.organisationType, 'hospital');
    expect(repo.lastFilters?.city, 'bangalore');
  });

  testWidgets('tapping a row navigates to /organisation-detail with the account\'s user id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2300, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminOrganisationsRepository([_item()]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          adminOrganisationsRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
        ],
        child: MaterialApp(
          home: const OrganisationsListScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Organisation Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('City Rehab Center'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/organisation-detail');
    expect(pushedArgs, 'u1');
  });

  testWidgets('tapping View Jobs redirects to /jobs pre-filtered to this organisation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2300, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminOrganisationsRepository([
      _item(userId: 'org-user-1', organisationName: 'City Rehab Center', organisationType: OrganisationType.rehab),
    ]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          adminOrganisationsRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
        ],
        child: MaterialApp(
          home: const OrganisationsListScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Jobs Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'View Jobs'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/jobs');
    final args = pushedArgs as JobsScreenInitialFilter;
    expect(args.postedByUserId, 'org-user-1');
    expect(args.postedByLabel, 'City Rehab Center');
    expect(args.organisationType, OrganisationType.rehab);
  });
}
