import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/core/network/api_exception.dart' as cg;
import 'package:nursenow_app/caregiver/features/jobs/widgets/feedback_widgets.dart' as cg_widgets;
import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart' as ph;
import 'package:nursenow_app/patient_hospital/features/individual/widgets/feedback_widgets.dart' as ph_widgets;

/// The patient_hospital and caregiver trees carry identical copies of these widgets
/// (same duplication precedent as RateCardButton), so the behaviour is checked on both.
void main() {
  group('patient tree', () {
    _suite(
      section: ({required mine, required received, required eligible, VoidCallback? onLeave}) => ph_widgets.FeedbackSection(
        aboutLabel: 'caregiver',
        mine: mine,
        received: received,
        eligible: eligible,
        onLeave: onLeave,
      ),
      open: (context, onSubmit) => ph_widgets.showFeedbackSheet(context, title: 'Rate Asha', onSubmit: onSubmit),
      apiError: (message) => ph.ApiException(message: message, code: 'FEEDBACK_002'),
      stars: (rating) => ph_widgets.StarsRow(rating: rating),
    );
  });

  group('caregiver tree', () {
    _suite(
      section: ({required mine, required received, required eligible, VoidCallback? onLeave}) => cg_widgets.FeedbackSection(
        aboutLabel: 'family',
        mine: mine,
        received: received,
        eligible: eligible,
        onLeave: onLeave,
      ),
      open: (context, onSubmit) => cg_widgets.showFeedbackSheet(context, title: 'Rate the family', onSubmit: onSubmit),
      apiError: (message) => cg.ApiException(message: message, code: 'FEEDBACK_002'),
      stars: (rating) => cg_widgets.StarsRow(rating: rating),
    );
  });
}

typedef _SectionBuilder = Widget Function({
  required FeedbackModel? mine,
  required FeedbackModel? received,
  required bool eligible,
  VoidCallback? onLeave,
});

void _suite({
  required _SectionBuilder section,
  required Future<bool> Function(BuildContext, Future<void> Function(int, String?)) open,
  required Exception Function(String) apiError,
  required Widget Function(int) stars,
}) {
  Future<void> pumpSection(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));

  group('FeedbackSection', () {
    testWidgets('shows nothing before the work has started and with nothing written', (tester) async {
      await pumpSection(tester, section(mine: null, received: null, eligible: false));
      expect(find.byKey(const Key('feedback-section')), findsNothing);
    });

    testWidgets('offers the button once the work has started', (tester) async {
      var taps = 0;
      await pumpSection(tester, section(mine: null, received: null, eligible: true, onLeave: () => taps++));
      await tester.tap(find.byKey(const Key('leave-feedback')));
      expect(taps, 1);
    });

    testWidgets('after writing, shows your feedback instead of the button', (tester) async {
      await pumpSection(
        tester,
        section(mine: const FeedbackModel(rating: 4, comment: 'Kind and punctual'), received: null, eligible: true),
      );
      expect(find.byKey(const Key('leave-feedback')), findsNothing);
      expect(find.byKey(const Key('feedback-mine')), findsOneWidget);
      expect(find.text('Kind and punctual'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsNWidgets(1));
    });

    testWidgets('shows what the other side wrote about you, even before you wrote yours', (tester) async {
      await pumpSection(
        tester,
        section(mine: null, received: const FeedbackModel(rating: 5, comment: 'Lovely'), eligible: true),
      );
      expect(find.byKey(const Key('feedback-received')), findsOneWidget);
      expect(find.text('Feedback about you'), findsOneWidget);
      expect(find.byKey(const Key('leave-feedback')), findsOneWidget);
    });

    testWidgets('a rating with no comment shows just the stars', (tester) async {
      await pumpSection(tester, section(mine: const FeedbackModel(rating: 3), received: null, eligible: true));
      expect(find.byKey(const Key('feedback-mine-comment')), findsNothing);
    });
  });

  group('the rate sheet', () {
    Future<List<List<Object?>>> openSheet(
      WidgetTester tester, {
      Future<void> Function(int, String?)? onSubmit,
    }) async {
      final calls = <List<Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => open(context, onSubmit ?? (r, c) async => calls.add([r, c])),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('asks for stars first: sending with none shows a message and sends nothing', (tester) async {
      final calls = await openSheet(tester);
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await tester.pump();
      expect(find.byKey(const Key('feedback-stars-error')), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('sends the chosen stars and the trimmed comment, then closes', (tester) async {
      final calls = await openSheet(tester);
      await tester.tap(find.byKey(const Key('feedback-star-4')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('feedback-comment')), '  Very caring  ');
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await tester.pumpAndSettle();
      expect(calls.single, [4, 'Very caring']);
      expect(find.byKey(const Key('feedback-submit')), findsNothing);
    });

    testWidgets('a blank comment is sent as none', (tester) async {
      final calls = await openSheet(tester);
      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('feedback-comment')), '    ');
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await tester.pumpAndSettle();
      expect(calls.single, [5, null]);
    });

    testWidgets('the comment is limited to ${Validation.feedbackCommentMaxLength} characters', (tester) async {
      await openSheet(tester);
      await tester.enterText(find.byKey(const Key('feedback-comment')), 'x' * 300);
      await tester.pump();
      final field = tester.widget<TextField>(find.byKey(const Key('feedback-comment')));
      expect(field.controller!.text.length, Validation.feedbackCommentMaxLength);
    });

    testWidgets('a server error stays inside the sheet and nothing closes', (tester) async {
      await openSheet(tester, onSubmit: (r, c) async => throw apiError('You have already left feedback for this job'));
      await tester.tap(find.byKey(const Key('feedback-star-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await tester.pumpAndSettle();
      expect(find.text('You have already left feedback for this job'), findsOneWidget);
      expect(find.byKey(const Key('feedback-submit')), findsOneWidget);
    });

    testWidgets('Not now closes without sending', (tester) async {
      final calls = await openSheet(tester);
      await tester.tap(find.byKey(const Key('feedback-cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byKey(const Key('feedback-submit')), findsNothing);
    });

    testWidgets('the stars can be changed before sending', (tester) async {
      final calls = await openSheet(tester);
      await tester.tap(find.byKey(const Key('feedback-star-2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('feedback-submit')));
      await tester.pumpAndSettle();
      expect(calls.single.first, 5);
    });
  });

  testWidgets('StarsRow draws five stars', (tester) async {
    await pumpSection(tester, stars(2));
    expect(find.byIcon(Icons.star), findsNWidgets(2));
    expect(find.byIcon(Icons.star_border), findsNWidgets(3));
  });
}
