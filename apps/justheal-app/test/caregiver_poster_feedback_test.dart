import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/features/jobs/widgets/feedback_widgets.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/job_poster_contact_card.dart';

void main() {
  const poster = JobPosterModel(fullName: 'Rao Family', phone: '+919876543210', isFamily: true);

  testWidgets('"Write feedback about the family" sits inside the Posted by box', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JobPosterContactCard(
            poster: poster,
            feedback: FeedbackSection(
              aboutLabel: 'family',
              leaveLabel: 'Write feedback about the family',
              mineTitle: 'Your feedback about the family',
              mine: null,
              received: null,
              eligible: true,
              onLeave: () => tapped++,
            ),
          ),
        ),
      ),
    ));
    final box = find.byType(JobPosterContactCard);
    expect(find.descendant(of: box, matching: find.text('Posted by')), findsOneWidget);
    expect(find.descendant(of: box, matching: find.text('Write feedback about the family')), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave-feedback')));
    expect(tapped, 1);
  });

  testWidgets('once written it reads "Your feedback about the family" with an Edit button, in the same box', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JobPosterContactCard(
            poster: poster,
            feedback: FeedbackSection(
              aboutLabel: 'family',
              leaveLabel: 'Write feedback about the family',
              mineTitle: 'Your feedback about the family',
              mine: FeedbackModel.tryParse({'rating': 4, 'comment': 'Kind people'}),
              received: null,
              eligible: true,
              onEdit: () {},
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Your feedback about the family'), findsOneWidget);
    expect(find.byKey(const Key('edit-feedback')), findsOneWidget);
  });

  testWidgets('no feedback widget means the Posted by box is just the contact details', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: JobPosterContactCard(poster: poster))));
    expect(find.byKey(const Key('feedback-section')), findsNothing);
  });

  testWidgets('what the family rated you stays a separate "Feedback about you" block, stars only', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeedbackSection(
          aboutLabel: 'family',
          mine: null,
          received: FeedbackModel.tryParse({'rating': 5, 'comment': 'Hidden comment'}),
          eligible: false,
        ),
      ),
    ));
    expect(find.text('Feedback about you'), findsOneWidget);
    expect(find.text('Your feedback'), findsNothing);
    expect(find.text('Hidden comment'), findsNothing);
  });
}
