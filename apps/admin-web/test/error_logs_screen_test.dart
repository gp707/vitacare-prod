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
import 'package:admin_web/features/error_logs/data/admin_error_logs_repository.dart';
import 'package:admin_web/features/error_logs/screens/error_logs_screen.dart';
import 'package:admin_web/shared/widgets/contact_actions.dart';

AdminErrorLogItem _error({
  String id = 'err-1',
  String? userId = 'u1',
  String? userFullName = 'Asha Rao',
  String? userPhone = '+919876543210',
  String? userRole = 'individual',
  int? patientNumber = 512,
  String message = 'column "duration_type" does not exist',
  String status = 'open',
  Map<String, dynamic>? requestContext = const {
    'body': {'phone': '+919876543210', 'code': '[redacted]', 'care_receiver': {'age': 74}},
    'query': {'page': '1'},
  },
  String? resolvedByName,
  String? resolutionNote,
}) {
  return AdminErrorLogItem(
    id: id,
    method: 'POST',
    path: '/v1/individual/requirements',
    statusCode: 500,
    message: message,
    stack: 'Error: boom\n    at somewhere.ts:1:1',
    userId: userId,
    userRole: userRole,
    userFullName: userFullName,
    userPhone: userPhone,
    patientNumber: patientNumber,
    ipAddress: '203.0.113.9',
    createdAt: DateTime.now().subtract(const Duration(minutes: 7)).toUtc().toIso8601String(),
    requestContext: requestContext,
    userAgent: 'Dart/3.6 (dart:io)',
    status: status,
    resolvedAt: status == 'resolved' ? DateTime.now().toUtc().toIso8601String() : null,
    resolvedByName: resolvedByName,
    resolutionNote: resolutionNote,
  );
}

AffectedUser _affected({
  String userId = 'u1',
  String fullName = 'Asha Rao',
  String phone = '+919876543210',
  int openCount = 2,
  int errorCount = 3,
}) {
  return AffectedUser(
    userId: userId,
    fullName: fullName,
    phone: phone,
    role: 'individual',
    patientNumber: 512,
    errorCount: errorCount,
    openCount: openCount,
    lastErrorAt: DateTime.now().subtract(const Duration(hours: 2)),
    lastErrorId: 'err-1',
    lastMessage: 'column "duration_type" does not exist',
    lastRequest: 'POST /v1/individual/requirements',
  );
}

PaginationMeta _meta(int total) => PaginationMeta(page: 1, limit: 20, total: total, totalPages: total == 0 ? 0 : 1);

class _FakeErrorLogsRepository extends AdminErrorLogsRepository {
  List<AdminErrorLogItem> errors;
  List<AffectedUser> affected;

  String? lastStatus;
  String? lastUserId;
  String? lastSearch;
  String? lastAffectedStatus;
  final resolved = <({String id, String? note})>[];
  final resolvedForUser = <({String userId, String? note})>[];

  _FakeErrorLogsRepository({this.errors = const [], this.affected = const []}) : super(Dio());

  @override
  Future<List<AdminDailyRequestStats>> getStats({int days = 7}) async =>
      [const AdminDailyRequestStats(date: '2026-10-24', totalRequests: 120, totalErrors: 3)];

  @override
  Future<AdminErrorLogsListResult> list({
    int page = 1,
    int limit = 20,
    String status = 'all',
    String? userId,
    String? search,
  }) async {
    lastStatus = status;
    lastUserId = userId;
    lastSearch = search;
    final filtered = errors.where((e) => status == 'all' || e.status == status).toList();
    return AdminErrorLogsListResult(items: filtered, meta: _meta(filtered.length));
  }

  @override
  Future<AffectedUsersResult> listAffectedUsers({int page = 1, int limit = 20, String status = 'open'}) async {
    lastAffectedStatus = status;
    return AffectedUsersResult(items: affected, meta: _meta(affected.length));
  }

  @override
  Future<void> resolve(String id, {String? note}) async {
    resolved.add((id: id, note: note));
    errors = errors
        .map((e) => e.id == id ? _error(id: e.id, status: 'resolved', resolutionNote: note, resolvedByName: 'Admin') : e)
        .toList();
  }

  @override
  Future<int> resolveAllForUser(String userId, {String? note}) async {
    resolvedForUser.add((userId: userId, note: note));
    final count = affected.where((a) => a.userId == userId).fold<int>(0, (sum, a) => sum + a.openCount);
    affected = affected.where((a) => a.userId != userId).toList();
    return count;
  }
}

Future<List<Uri>> _pump(WidgetTester tester, _FakeErrorLogsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(2400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  final launched = <Uri>[];
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
        adminErrorLogsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: MaterialApp(
        home: const ErrorLogsScreen(),
        onGenerateRoute: (settings) =>
            MaterialPageRoute(builder: (_) => Scaffold(body: Text('opened ${settings.name}:${settings.arguments}'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return launched;
}

void main() {
  testWidgets('Errors tab defaults to Open and shows who it happened to, their phone and the message', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error(), _error(id: 'err-2', status: 'resolved')]);
    await _pump(tester, repo);

    expect(repo.lastStatus, 'open');
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('column "duration_type" does not exist'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('7 min ago'), findsOneWidget);
    // Only the open one while the Open filter is active.
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
  });

  testWidgets('the Call and WhatsApp buttons launch the phone dialer and a WhatsApp chat for that number', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    final launched = await _pump(tester, repo);

    await tester.tap(find.byTooltip('Call +919876543210'));
    await tester.tap(find.byTooltip('WhatsApp +919876543210'));
    await tester.pumpAndSettle();

    expect(launched, hasLength(2));
    expect(launched[0].scheme, 'tel');
    expect(launched[0].path, '+919876543210');
    expect(launched[1].toString(), 'https://wa.me/919876543210');
  });

  testWidgets('an anonymous error has no customer and no call buttons', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error(userId: null, userFullName: null, userPhone: null, userRole: null, patientNumber: null)]);
    await _pump(tester, repo);

    expect(find.byIcon(Icons.call), findsNothing);
    await tester.tap(find.textContaining('POST /v1/individual/requirements'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unauthenticated request', findRichText: true), findsOneWidget);
  });

  testWidgets('the detail dialog shows the real request data (secrets redacted), client, IP and a call button', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    final launched = await _pump(tester, repo);

    await tester.tap(find.text('column "duration_type" does not exist'));
    await tester.pumpAndSettle();

    expect(find.text('Who it happened to'), findsOneWidget);
    expect(find.text('PAT-512 · Asha Rao · Patient/Family · +919876543210'), findsOneWidget);
    expect(find.text('What they were doing (request data)'), findsOneWidget);
    // The pretty-printed, already-redacted request body.
    expect(find.textContaining('"phone": "+919876543210"'), findsOneWidget);
    expect(find.textContaining('"code": "[redacted]"'), findsOneWidget);
    expect(find.textContaining('"age": 74'), findsOneWidget);
    expect(find.textContaining('PINs, codes, passwords and tokens are never stored'), findsOneWidget);
    expect(find.textContaining('Dart/3.6', findRichText: true), findsOneWidget);
    expect(find.textContaining('203.0.113.9', findRichText: true), findsOneWidget);
    expect(find.textContaining('Error: boom'), findsOneWidget);

    await tester.tap(find.byTooltip('Call +919876543210').last);
    await tester.pumpAndSettle();
    expect(launched.single.scheme, 'tel');
  });

  testWidgets('the detail dialog says so when no request data was captured', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error(requestContext: null)]);
    await _pump(tester, repo);
    await tester.tap(find.text('column "duration_type" does not exist'));
    await tester.pumpAndSettle();
    expect(find.text('No request data was captured for this error.'), findsOneWidget);
  });

  testWidgets('Mark resolved asks for a note, sends it, and the error leaves the Open list', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Resolve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What was done? (optional)'), 'Called, asked to retry');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark resolved'));
    await tester.pumpAndSettle();

    expect(repo.resolved.single.id, 'err-1');
    expect(repo.resolved.single.note, 'Called, asked to retry');
    expect(find.text('No open errors. Nothing needs attention.'), findsOneWidget);
  });

  testWidgets('cancelling the note dialog resolves nothing', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Resolve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.resolved, isEmpty);
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
  });

  testWidgets('a resolved error shows who handled it and their note, and offers no Resolve action', (tester) async {
    final repo = _FakeErrorLogsRepository(
      errors: [_error(status: 'resolved', resolvedByName: 'Pankaj', resolutionNote: 'Phoned and re-registered')],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Resolve'), findsNothing);

    await tester.tap(find.text('column "duration_type" does not exist'));
    await tester.pumpAndSettle();
    expect(find.text('Resolved'), findsWidgets);
    expect(find.textContaining('Pankaj', findRichText: true), findsOneWidget);
    expect(find.textContaining('Phoned and re-registered', findRichText: true), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Mark resolved'), findsNothing);
  });

  testWidgets('status filter and search are sent to the backend', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();
    expect(repo.lastStatus, 'resolved');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(repo.lastStatus, 'all');

    await tester.enterText(find.widgetWithText(TextField, 'Search path or message'), '  /auth/login ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.lastSearch, '/auth/login');
  });

  testWidgets('Affected users tab lists each person with counts, phone and last error', (tester) async {
    final repo = _FakeErrorLogsRepository(affected: [_affected()]);
    final launched = await _pump(tester, repo);

    await tester.tap(find.widgetWithText(Tab, 'Affected users'));
    await tester.pumpAndSettle();

    expect(repo.lastAffectedStatus, 'open');
    expect(find.text('PAT-512 · Asha Rao'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('2 open / 3'), findsOneWidget);
    expect(find.textContaining('2 h ago'), findsOneWidget);
    expect(find.textContaining('POST /v1/individual/requirements'), findsOneWidget);

    await tester.tap(find.byTooltip('Call +919876543210'));
    await tester.pumpAndSettle();
    expect(launched.single.scheme, 'tel');

    await tester.tap(find.text('Everyone affected'));
    await tester.pumpAndSettle();
    expect(repo.lastAffectedStatus, 'all');
  });

  testWidgets('View errors jumps to the Errors tab narrowed to that person, and the chip clears the filter', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()], affected: [_affected()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(Tab, 'Affected users'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'View errors'));
    await tester.pumpAndSettle();

    expect(repo.lastUserId, 'u1');
    expect(find.text('Only PAT-512 · Asha Rao'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(repo.lastUserId, isNull);
    expect(find.textContaining('Only PAT-512'), findsNothing);
  });

  testWidgets('Mark contacted resolves all of a person\'s open errors with a note and refreshes both lists', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()], affected: [_affected()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(Tab, 'Affected users'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Mark contacted'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What was done? (optional)'), 'Phoned them');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark contacted & resolved'));
    await tester.pumpAndSettle();

    expect(repo.resolvedForUser.single.userId, 'u1');
    expect(repo.resolvedForUser.single.note, 'Phoned them');
    expect(find.text('Resolved 2 errors for Asha Rao.'), findsOneWidget);
    expect(find.text('Nobody to follow up with — no one has open errors.'), findsOneWidget);
  });

  testWidgets('empty states', (tester) async {
    await _pump(tester, _FakeErrorLogsRepository());
    expect(find.text('No open errors. Nothing needs attention.'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Affected users'));
    await tester.pumpAndSettle();
    expect(find.text('Nobody to follow up with — no one has open errors.'), findsOneWidget);
  });

  testWidgets('opens the person\'s own detail screen from the error dialog', (tester) async {
    final repo = _FakeErrorLogsRepository(errors: [_error()]);
    await _pump(tester, repo);
    await tester.tap(find.text('column "duration_type" does not exist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PAT-512 · Asha Rao · Patient/Family · +919876543210'));
    await tester.pumpAndSettle();
    expect(find.text('opened /individual-detail:u1'), findsOneWidget);
  });

  test('phone helpers build the right URIs', () {
    expect(phoneCallUri('+919876543210').toString(), 'tel:+919876543210');
    expect(whatsAppUri('+91 98765-43210').toString(), 'https://wa.me/919876543210');
  });
}
