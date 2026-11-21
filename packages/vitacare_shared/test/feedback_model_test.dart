import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

void main() {
  group('FeedbackModel / FeedbackState', () {
    test('reads the API shape', () {
      final state = FeedbackState.fromJson({
        'can_give': false,
        'reason': null,
        'mine': {'rating': 4, 'comment': 'Kind', 'created_at': '2026-11-20T10:00:00Z'},
        'received': null,
      });
      expect(state.canGive, isFalse);
      expect(state.mine!.rating, 4);
      expect(state.mine!.comment, 'Kind');
      expect(state.received, isNull);
    });

    test('reads whether the feedback can still be changed', () {
      expect(FeedbackState.fromJson({'can_give': false, 'can_edit': true}).canEdit, isTrue);
      expect(FeedbackState.fromJson({'can_give': true}).canEdit, isFalse);
    });

    test('a missing or malformed value is no feedback', () {
      expect(FeedbackModel.tryParse(null), isNull);
      expect(FeedbackModel.tryParse('nope'), isNull);
    });

    test('applications carry my_feedback / their_feedback', () {
      final json = {
        'status': 'accepted',
        'decided_by_admin': false,
        'my_feedback': {'rating': 5, 'comment': null},
        'their_feedback': {'rating': 3, 'comment': 'ok'},
      };
      final app = MyApplicationModel.fromJson(json);
      expect(app.myFeedback!.rating, 5);
      expect(app.theirFeedback!.comment, 'ok');
      expect(MyApplicationModel.fromJson({'status': 'applied', 'decided_by_admin': false}).myFeedback, isNull);
    });

    test('the poster says whether it is a family', () {
      expect(JobPosterModel.fromJson({'full_name': 'A', 'phone': '1', 'is_family': true}).isFamily, isTrue);
      expect(JobPosterModel.fromJson({'full_name': 'A', 'phone': '1'}).isFamily, isFalse);
    });
  });

  group('feedbackEligible (decides only whether to show the button)', () {
    final today = DateTime(2026, 11, 20);
    test('needs acceptance and a start date that has arrived', () {
      expect(feedbackEligible(acceptedAt: 'x', agreedStartDate: '2026-11-18', today: today), isTrue);
      expect(feedbackEligible(acceptedAt: 'x', agreedStartDate: '2026-11-20', today: today), isTrue);
      expect(feedbackEligible(acceptedAt: 'x', agreedStartDate: '2026-11-21', today: today), isFalse);
      expect(feedbackEligible(acceptedAt: null, agreedStartDate: '2026-11-18', today: today), isFalse);
      expect(feedbackEligible(acceptedAt: 'x', agreedStartDate: null, today: today), isFalse);
      expect(feedbackEligible(acceptedAt: 'x', agreedStartDate: 'bad', today: today), isFalse);
    });
  });

  group('cleanFeedbackComment', () {
    test('trims, treats blank as none and caps the length', () {
      expect(cleanFeedbackComment('  hi  '), 'hi');
      expect(cleanFeedbackComment('   '), isNull);
      expect(cleanFeedbackComment('x' * 300)!.length, Validation.feedbackCommentMaxLength);
    });
  });
}
