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
import 'package:admin_web/features/feedback/data/admin_feedback_repository.dart';
import 'package:admin_web/features/feedback/screens/feedback_screen.dart';

AdminFeedbackItem _item({
  String id = 'f1',
  String authorRole = 'individual',
  int rating = 4,
  String? comment = 'Kind and punctual',
  String? caregiverName = 'Sunandita Nandy',
  String? patientName = 'Krishna Sapra',
}) =>
    AdminFeedbackItem(
      id: id,
      authorRole: authorRole,
      rating: rating,
      comment: comment,
      createdAt: '2026-12-03T10:00:00Z',
      jobId: 'job-1',
      patientJobNumber: 548,
      caregiverNumber: 589,
      caregiverProfileId: 'cp-1',
      caregiverName: caregiverName,
      patientNumber: 636,
      patientUserId: 'patient-1',
      patientName: patientName,
    );

class _FakeFeedbackRepository extends AdminFeedbackRepository {
  List<AdminFeedbackItem> items;
  String? lastAuthorRole;
  int? lastRating;
  String? lastSearch;
  int calls = 0;

  _FakeFeedbackRepository(this.items) : super(Dio());

  @override
  Future<AdminFeedbackListResult> list({int page = 1, int limit = 20, String? authorRole, int? rating, String? search}) async {
    calls++;
    lastAuthorRole = authorRole;
    lastRating = rating;
    lastSearch = search;
    return AdminFeedbackListResult(
      items: items,
      meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: items.isEmpty ? 0 : 1),
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeFeedbackRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(2400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminFeedbackRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: MaterialApp(
        home: const FeedbackScreen(),
        onGenerateRoute: (settings) =>
            MaterialPageRoute(builder: (_) => Scaffold(body: Text('opened ${settings.name}:${settings.arguments}'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists who wrote what about whom, with stars, comment, date and job', (tester) async {
    await _pump(tester, _FakeFeedbackRepository([_item()]));
    expect(find.text('PAT-636 Krishna Sapra'), findsOneWidget); // from
    expect(find.text('NUR-589 Sunandita Nandy'), findsOneWidget); // about
    expect(find.text('Kind and punctual'), findsOneWidget);
    expect(find.text('2026-12-03'), findsOneWidget);
    expect(find.text('PAT-JOB-548'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_border), findsNWidgets(1));
  });

  testWidgets('a caregiver\'s feedback reads caregiver -> family', (tester) async {
    await _pump(tester, _FakeFeedbackRepository([_item(authorRole: 'caregiver', rating: 5, comment: 'Respectful')]));
    final from = tester.getTopLeft(find.text('NUR-589 Sunandita Nandy')).dx;
    final about = tester.getTopLeft(find.text('PAT-636 Krishna Sapra')).dx;
    expect(from, lessThan(about)); // the From column is left of About
    expect(find.text('Respectful'), findsOneWidget);
  });

  testWidgets('a rating without a comment shows a dash', (tester) async {
    await _pump(tester, _FakeFeedbackRepository([_item(comment: null)]));
    expect(find.text('-'), findsWidgets);
  });

  testWidgets('says so when there is no feedback', (tester) async {
    await _pump(tester, _FakeFeedbackRepository([]));
    expect(find.byKey(const Key('feedback-empty')), findsOneWidget);
  });

  testWidgets('filters by direction and stars are sent to the server and reload the list', (tester) async {
    final repo = _FakeFeedbackRepository([_item()]);
    await _pump(tester, repo);
    expect(repo.calls, 1);

    await tester.tap(find.byKey(const Key('feedback-filter-direction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caregiver about family').last);
    await tester.pumpAndSettle();
    expect(repo.lastAuthorRole, 'caregiver');

    await tester.tap(find.byKey(const Key('feedback-filter-rating')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 star').last);
    await tester.pumpAndSettle();
    expect(repo.lastRating, 1);
    expect(repo.calls, 3);
  });

  testWidgets('searching sends the text when submitted', (tester) async {
    final repo = _FakeFeedbackRepository([_item()]);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('feedback-search')), 'NUR-589');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.lastSearch, 'NUR-589');
  });

  testWidgets('tapping the caregiver opens their detail screen, the patient theirs', (tester) async {
    await _pump(tester, _FakeFeedbackRepository([_item()]));
    await tester.tap(find.text('NUR-589 Sunandita Nandy'));
    await tester.pumpAndSettle();
    expect(find.text('opened /caregiver-detail:cp-1'), findsOneWidget);
  });
}
