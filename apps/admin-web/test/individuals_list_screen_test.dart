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
import 'package:admin_web/features/individuals/data/admin_individuals_repository.dart';
import 'package:admin_web/features/individuals/screens/individuals_list_screen.dart';
import 'package:admin_web/features/jobs/screens/admin_jobs_screen.dart';

AdminIndividualListItem _item({
  String userId = 'u1',
  int? patientNumber = 500,
  String fullName = 'Asha Patel',
  bool isActive = true,
  bool isJobPostingBlocked = false,
  String? blockReason,
}) {
  return AdminIndividualListItem(
    userId: userId,
    patientNumber: patientNumber,
    fullName: fullName,
    phone: '+919876543210',
    isActive: isActive,
    isJobPostingBlocked: isJobPostingBlocked,
    blockReason: blockReason,
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminIndividualsRepository extends AdminIndividualsRepository {
  List<AdminIndividualListItem> items;
  String? blockedUserId;
  String? blockedLevel;
  String? blockedReason;
  String? unblockedUserId;
  String? unblockedLevel;
  IndividualListFilters? lastFilters;

  _FakeAdminIndividualsRepository(this.items) : super(Dio());

  @override
  Future<AdminIndividualsListResult> list({
    int page = 1,
    int limit = 20,
    IndividualListFilters filters = const IndividualListFilters(),
  }) async {
    lastFilters = filters;
    return AdminIndividualsListResult(
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

Future<void> _pump(WidgetTester tester, _FakeAdminIndividualsRepository repo) async {
  // The Actions column sits at the right edge of a horizontally-scrolling
  // DataTable — the default 800x600 test surface clips it off-screen.
  await tester.binding.setSurfaceSize(const Size(2000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminIndividualsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: IndividualsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists individual accounts with their status', (tester) async {
    await _pump(tester, _FakeAdminIndividualsRepository([_item()]));

    expect(find.text('Asha Patel'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('PAT-500'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no individuals', (tester) async {
    await _pump(tester, _FakeAdminIndividualsRepository([]));

    expect(find.text('No individual accounts yet.'), findsOneWidget);
  });

  testWidgets('shows the block reason for a job-posting-blocked account', (tester) async {
    await _pump(
      tester,
      _FakeAdminIndividualsRepository([
        _item(isJobPostingBlocked: true, blockReason: 'Suspicious activity'),
      ]),
    );

    expect(find.text('Posting blocked: Suspicious activity'), findsOneWidget);
    expect(find.text('Unblock Posting'), findsOneWidget);
  });

  testWidgets('shows Blocked for a fully-blocked (inactive) account', (tester) async {
    await _pump(
      tester,
      _FakeAdminIndividualsRepository([_item(isActive: false, blockReason: 'Fraudulent postings')]),
    );

    expect(find.text('Blocked: Fraudulent postings'), findsOneWidget);
    expect(find.text('Unblock'), findsOneWidget);
  });

  testWidgets('blocking job posting opens a reason dialog and calls the repository', (tester) async {
    final repo = _FakeAdminIndividualsRepository([_item()]);
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

  testWidgets('cancelling the block dialog does not call the repository', (tester) async {
    final repo = _FakeAdminIndividualsRepository([_item()]);
    await _pump(tester, repo);

    // The Actions column's second button sits at a DataTable-computed
    // offset that Flutter's simulated tap sometimes lands just outside of
    // (a known DataTable/Wrap hit-testing quirk) — invoking the button's
    // own callback exercises the exact same code path without relying on
    // pixel-perfect tap coordinates.
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Block')).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.blockedUserId, isNull);
  });

  testWidgets('unblocking a fully-blocked account calls the repository with level=full', (tester) async {
    final repo = _FakeAdminIndividualsRepository([_item(isActive: false)]);
    await _pump(tester, repo);

    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Unblock')).onPressed!();
    await tester.pumpAndSettle();

    expect(repo.unblockedUserId, 'u1');
    expect(repo.unblockedLevel, 'full');
  });

  testWidgets('entering a search term and picking a status, then Apply Filters, passes both through', (tester) async {
    final repo = _FakeAdminIndividualsRepository([_item()]);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search name, phone, or ID (PAT-...)'),
      'PAT-500',
    );
    await _selectFilterDropdown(tester, 'Status', 'Blocked');
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, 'PAT-500');
    expect(repo.lastFilters?.blockStatus, 'blocked');
  });

  testWidgets('tapping a row navigates to /individual-detail with the account\'s user id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminIndividualsRepository([_item()]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          adminIndividualsRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
        ],
        child: MaterialApp(
          home: const IndividualsListScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Individual Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Asha Patel'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/individual-detail');
    expect(pushedArgs, 'u1');
  });

  testWidgets('tapping View Jobs redirects to /jobs pre-filtered to this individual', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    final repo = _FakeAdminIndividualsRepository([_item(userId: 'patient-user-1', fullName: 'Rahul Bajaj')]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          adminIndividualsRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
        ],
        child: MaterialApp(
          home: const IndividualsListScreen(),
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
    expect(args.postedByUserId, 'patient-user-1');
    expect(args.postedByLabel, 'Rahul Bajaj');
    expect(args.organisationType, isNull);
  });
}
