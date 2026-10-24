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
import 'package:admin_web/features/insights/data/admin_insights_repository.dart';
import 'package:admin_web/features/insights/screens/insights_screen.dart';
import 'package:admin_web/shared/widgets/contact_actions.dart';

InsightAccount _account({
  String userId = 'u1',
  String fullName = 'Ramesh Kumar',
  String phone = '+919876543210',
  String role = 'caregiver',
  int? caregiverNumber = 500,
  int? patientNumber,
  int? orgNumber,
  Duration lastSeenAgo = const Duration(hours: 3),
  Duration registeredAgo = const Duration(days: 4),
  int? postings,
  int? applicants,
  int? pendingApplicants,
  String? verificationStatus = 'pending_call',
}) {
  final now = DateTime.now();
  return InsightAccount(
    userId: userId,
    fullName: fullName,
    phone: phone,
    role: role,
    createdAt: now.subtract(registeredAgo),
    lastSeenAt: now.subtract(lastSeenAgo),
    caregiverNumber: caregiverNumber,
    caregiverProfileId: role == 'caregiver' ? 'profile-$userId' : null,
    verificationStatus: verificationStatus,
    patientNumber: patientNumber,
    orgNumber: orgNumber,
    postings: postings,
    applicants: applicants,
    pendingApplicants: pendingApplicants,
    firstAppliedAt: applicants == null ? null : now.subtract(const Duration(days: 2)),
  );
}

LoginProblem _problem({
  String phone = '+919876543210',
  int attempts = 3,
  int wrongPinAttempts = 3,
  String reason = 'wrong_pin',
  String app = 'nursenow',
  String status = 'locked_out',
  String? userId = 'u1',
  String? fullName = 'Asha Rao',
  String? role = 'individual',
  int? patientNumber = 512,
  Duration lastAgo = const Duration(minutes: 20),
}) {
  final now = DateTime.now();
  return LoginProblem(
    phone: phone,
    attempts: attempts,
    wrongPinAttempts: wrongPinAttempts,
    firstAttemptAt: now.subtract(lastAgo + const Duration(hours: 1)),
    lastAttemptAt: now.subtract(lastAgo),
    lastReason: reason,
    lastApp: app,
    status: status,
    userId: userId,
    fullName: fullName,
    role: role,
    patientNumber: patientNumber,
  );
}

InsightsPage<InsightAccount> _page(List<InsightAccount> items) => InsightsPage(
      items: items,
      meta: PaginationMeta(page: 1, limit: 25, total: items.length, totalPages: items.isEmpty ? 0 : 1),
    );

class _FakeInsightsRepository extends AdminInsightsRepository {
  List<InsightAccount> active;
  List<InsightAccount> inactive;
  List<InsightAccount> posters;
  List<InsightAccount> caregivers;
  List<TopActionRow> top;
  List<LoginProblem> loginProblems;

  int? lastActiveHours;
  String? lastActiveRole;
  int? lastMinAgeHours;
  String? lastTopKind;
  int? lastTopDays;
  String? lastTopFlow;
  int? lastLoginDays;
  String? lastLoginStatus;

  _FakeInsightsRepository({
    this.active = const [],
    this.inactive = const [],
    this.posters = const [],
    this.caregivers = const [],
    this.top = const [],
    this.loginProblems = const [],
  }) : super(Dio());

  @override
  Future<InsightsSummary> getSummary() async => InsightsSummary(
        activeUsers24h: 7,
        activeUsers48h: 11,
        activeUsers7d: 19,
        inactiveSinceRegistration: 4,
        postersWithoutAccepted: 3,
        caregiversNeverApplied: 5,
        loginProblems: 2,
      );

  @override
  Future<InsightsPage<InsightAccount>> listActiveUsers({
    required int hours,
    String? role,
    int page = 1,
    int limit = 25,
  }) async {
    lastActiveHours = hours;
    lastActiveRole = role;
    return _page(active);
  }

  @override
  Future<InsightsPage<InsightAccount>> listInactiveSinceRegistration({
    required int minAgeHours,
    String? role,
    int page = 1,
    int limit = 25,
  }) async {
    lastMinAgeHours = minAgeHours;
    return _page(inactive);
  }

  @override
  Future<InsightsPage<InsightAccount>> listPostersWithoutAccepted({int page = 1, int limit = 25}) async =>
      _page(posters);

  @override
  Future<InsightsPage<InsightAccount>> listCaregiversNeverApplied({int page = 1, int limit = 25}) async =>
      _page(caregivers);

  @override
  Future<InsightsPage<LoginProblem>> listLoginProblems({
    int days = 7,
    String status = 'locked_out',
    int page = 1,
    int limit = 25,
  }) async {
    lastLoginDays = days;
    lastLoginStatus = status;
    return InsightsPage(
      items: loginProblems,
      meta: PaginationMeta(page: 1, limit: 25, total: loginProblems.length, totalPages: loginProblems.isEmpty ? 0 : 1),
    );
  }

  @override
  Future<List<TopActionRow>> getTopActions({
    required String kind,
    required int days,
    String? flow,
    int limit = 50,
  }) async {
    lastTopKind = kind;
    lastTopDays = days;
    lastTopFlow = flow;
    return top;
  }
}

final launched = <Uri>[];

Future<List<String>> _pump(WidgetTester tester, _FakeInsightsRepository repo) async {
  launched.clear();
  await tester.binding.setSurfaceSize(const Size(2400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  final pushed = <String>[];
  final originalLauncher = uriLauncher;
  uriLauncher = (uri) async {
    launched.add(uri);
    return true;
  };
  addTearDown(() => uriLauncher = originalLauncher);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminInsightsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: MaterialApp(
        home: const InsightsScreen(),
        onGenerateRoute: (settings) {
          pushed.add('${settings.name}:${settings.arguments}');
          return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('detail page')));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every headline count in the summary cards', (tester) async {
    await _pump(tester, _FakeInsightsRepository());

    expect(find.text('Insights'), findsWidgets);
    for (final count in ['7', '11', '19', '4', '3', '5', '2']) {
      expect(find.text(count), findsOneWidget, reason: 'summary card showing $count');
    }
  });

  testWidgets('Active users: lists name, display id, phone and last activity; 48 h and role filters reload', (tester) async {
    final repo = _FakeInsightsRepository(active: [
      _account(),
      _account(
        userId: 'u2',
        fullName: 'Asha Rao',
        phone: '+919000000002',
        role: 'individual',
        caregiverNumber: null,
        patientNumber: 512,
        lastSeenAgo: const Duration(minutes: 5),
      ),
    ]);
    await _pump(tester, repo);

    expect(repo.lastActiveHours, 24);
    expect(find.text('NUR-500 · Ramesh Kumar'), findsOneWidget);
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Patient/Family'), findsOneWidget);
    expect(find.textContaining('5 min ago'), findsOneWidget);
    expect(find.textContaining('3 h ago'), findsOneWidget);

    await tester.tap(find.text('48 h'));
    await tester.pumpAndSettle();
    expect(repo.lastActiveHours, 48);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(repo.lastActiveHours, 168);

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caregivers').last);
    await tester.pumpAndSettle();
    expect(repo.lastActiveRole, 'caregiver');
  });

  testWidgets('Active users: friendly empty state', (tester) async {
    await _pump(tester, _FakeInsightsRepository());
    expect(find.textContaining('Nobody has been active in this window yet'), findsOneWidget);
  });

  testWidgets('tapping an account opens that account\'s own detail screen, per role', (tester) async {
    final repo = _FakeInsightsRepository(active: [
      _account(),
      _account(userId: 'u2', fullName: 'Asha Rao', role: 'individual', caregiverNumber: null, patientNumber: 512),
      _account(userId: 'u3', fullName: 'City Hospital', role: 'organisation', caregiverNumber: null, orgNumber: 77),
    ]);
    final pushed = await _pump(tester, repo);

    await tester.tap(find.text('NUR-500 · Ramesh Kumar'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/caregiver-detail:profile-u1');
    Navigator.of(tester.element(find.text('detail page'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('PAT-512 · Asha Rao'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/individual-detail:u2');
    Navigator.of(tester.element(find.text('detail page'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('ORG-77 · City Hospital'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/organisation-detail:u3');
  });

  testWidgets('Most used buttons: ranks taps with counts and people, and Screens/period/flow switches reload', (tester) async {
    final repo = _FakeInsightsRepository(top: const [
      TopActionRow(kind: 'tap', flow: 'individual', screen: '/home', action: 'rate_card', count: 42, uniqueUsers: 9),
      TopActionRow(kind: 'tap', flow: 'auth', screen: '/login', action: 'log_in', count: 30, uniqueUsers: 12),
      TopActionRow(kind: 'tap', flow: 'auth', screen: '/login', action: 'forgot_pin', count: 6, uniqueUsers: 0),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Most used buttons');

    expect(repo.lastTopKind, 'tap');
    expect(repo.lastTopDays, 7);
    expect(find.text('rate card'), findsOneWidget);
    expect(find.text('log in'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Login / registration'), findsWidgets);
    // Pre-login taps have no countable people: a dash, never "0".
    expect(find.text('forgot pin'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);
    expect(find.textContaining('before login'), findsOneWidget);

    await tester.tap(find.text('Screens'));
    await tester.pumpAndSettle();
    expect(repo.lastTopKind, 'screen');

    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(repo.lastTopDays, 30);
  });

  testWidgets('Most used buttons: explains why it is empty', (tester) async {
    await _pump(tester, _FakeInsightsRepository());
    await _openTab(tester, 'Most used buttons');
    expect(find.textContaining('No usage recorded for this selection yet'), findsOneWidget);
  });

  testWidgets('Never came back: lists accounts that registered and left, with the age filter', (tester) async {
    final repo = _FakeInsightsRepository(inactive: [
      _account(fullName: 'Gone Person', phone: '+919111111111', registeredAgo: const Duration(days: 9)),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Never came back');

    expect(repo.lastMinAgeHours, 24);
    expect(find.text('NUR-500 · Gone Person'), findsOneWidget);
    expect(find.text('+919111111111'), findsOneWidget);
    expect(find.text('9 d ago'), findsOneWidget);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(repo.lastMinAgeHours, 168);
  });

  testWidgets('No candidate accepted: shows postings, applicants and awaiting-decision counts', (tester) async {
    final repo = _FakeInsightsRepository(posters: [
      _account(
        userId: 'p1',
        fullName: 'Asha Rao',
        role: 'individual',
        caregiverNumber: null,
        patientNumber: 512,
        postings: 1,
        applicants: 4,
        pendingApplicants: 3,
      ),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'No candidate accepted');

    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.textContaining('2 d ago'), findsOneWidget);
  });

  testWidgets('Caregivers not applied: lists verification status and waiting time', (tester) async {
    final repo = _FakeInsightsRepository(caregivers: [
      _account(fullName: 'Idle Nurse', verificationStatus: 'available', registeredAgo: const Duration(days: 12)),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Caregivers not applied');

    expect(find.text('NUR-500 · Idle Nurse'), findsOneWidget);
    expect(find.text('available'), findsOneWidget);
    expect(find.text('12 d ago'), findsOneWidget);
  });

  testWidgets('every account report has Call and WhatsApp buttons for the person\'s phone', (tester) async {
    final repo = _FakeInsightsRepository(active: [_account(phone: '+919111111111')]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Call +919111111111'));
    await tester.tap(find.byTooltip('WhatsApp +919111111111'));
    await tester.pumpAndSettle();

    expect(launched.map((u) => u.toString()), ['tel:+919111111111', 'https://wa.me/919111111111']);
  });

  testWidgets('Login problems: lists who is stuck, why, how many tries, with the Still-stuck filter by default', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [
      _problem(),
      _problem(
        phone: '+919000000009',
        attempts: 1,
        wrongPinAttempts: 0,
        reason: 'unknown_account',
        userId: null,
        fullName: null,
        role: null,
        patientNumber: null,
      ),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Login problems');

    expect(repo.lastLoginDays, 7);
    expect(repo.lastLoginStatus, 'locked_out');
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('No account'), findsOneWidget);
    expect(find.text('No account with this number'), findsOneWidget);
    expect(find.text('Still stuck'), findsWidgets);
    expect(find.textContaining('20 min ago'), findsWidgets);
    expect(find.textContaining('PIN that was tried is never stored'), findsOneWidget);
  });

  testWidgets('Login problems: a person with no account can still be called, and an account opens its detail screen', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [
      _problem(),
      _problem(phone: '+919000000009', reason: 'unknown_account', userId: null, fullName: null, role: null, patientNumber: null),
    ]);
    final pushed = await _pump(tester, repo);
    await _openTab(tester, 'Login problems');

    await tester.tap(find.byTooltip('Call +919000000009'));
    await tester.pumpAndSettle();
    expect(launched.single.toString(), 'tel:+919000000009');

    await tester.tap(find.text('PAT-512 · Asha Rao'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/individual-detail:u1');
  });

  testWidgets('Login problems: explains a wrong-login-type attempt in plain words', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [
      _problem(reason: 'wrong_app', app: 'nursejobs', attempts: 2, wrongPinAttempts: 0),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Login problems');
    expect(find.text('Used the caregiver login, but this is a Patient/Family account'), findsOneWidget);
  });

  testWidgets('Login problems: a mix of wrong PINs and other failures shows the PIN count, and recovered rows say so', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [
      _problem(attempts: 5, wrongPinAttempts: 3, status: 'recovered'),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'Login problems');
    expect(find.text('5 (3 wrong PIN)'), findsOneWidget);
    expect(find.text('Got in since'), findsWidgets);
  });

  testWidgets('Login problems: status and window filters reload the list', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [_problem()]);
    await _pump(tester, repo);
    await _openTab(tester, 'Login problems');

    await tester.tap(find.text('Got in since'));
    await tester.pumpAndSettle();
    expect(repo.lastLoginStatus, 'recovered');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(repo.lastLoginStatus, 'all');

    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(repo.lastLoginDays, 30);
  });

  testWidgets('Login problems: friendly empty states', (tester) async {
    final repo = _FakeInsightsRepository();
    await _pump(tester, repo);
    await _openTab(tester, 'Login problems');
    expect(find.text('Nobody is stuck. Everyone whose login failed has since got in.'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('No failed logins in this window.'), findsOneWidget);
  });

  testWidgets('clicking the "Can\'t log in" card jumps to the Login problems tab', (tester) async {
    final repo = _FakeInsightsRepository(loginProblems: [_problem()]);
    await _pump(tester, repo);
    await tester.tap(find.text("Can't log in"));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN'), findsOneWidget);
  });

  testWidgets('clicking a summary card jumps to its tab', (tester) async {
    final repo = _FakeInsightsRepository(
      inactive: [_account(fullName: 'Gone Person')],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Never came back').first);
    await tester.pumpAndSettle();
    expect(find.text('NUR-500 · Gone Person'), findsOneWidget);
  });
}
