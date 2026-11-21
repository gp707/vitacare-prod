import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/agreed_terms_box.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/job_detail_card.dart';

void main() {
  testWidgets('shows the salary in the job\'s unit and the start date in words', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AgreedTermsBox(salary: 800, perUnit: 'day', startDate: '2026-11-20')),
    ));
    expect(find.text('Agreed with the family'), findsOneWidget);
    expect(find.text('Salary: ₹800 per day'), findsOneWidget);
    expect(find.text('Start date: 20 Nov 2026'), findsOneWidget);
    // Just the two agreed facts: no leave, no next-salary box, no salary history any more.
    expect(find.byKey(const Key('leave-section')), findsNothing);
    expect(find.textContaining('Next salary'), findsNothing);
    expect(find.textContaining('Salary history'), findsNothing);
  });

  testWidgets('the whole box is two lines at most: the title, then salary and start date on one line', (tester) async {
    for (final width in [360.0, 280.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: const AgreedTermsBox(salary: 6600, perUnit: 'day', startDate: '2026-11-01')),
          ),
        ),
      ));
      final title = tester.getRect(find.text('Agreed with the family'));
      final salary = tester.getRect(find.text('Salary: ₹6,600 per day'));
      final start = tester.getRect(find.text('Start date: 1 Nov 2026'));
      // salary and start date sit on the same line, below the title
      expect((salary.center.dy - start.center.dy).abs(), lessThan(4), reason: 'width $width');
      expect(salary.top, greaterThanOrEqualTo(title.bottom - 0.5), reason: 'width $width');
      // neither is wrapped onto a second line of its own
      expect(salary.height, lessThan(24), reason: 'width $width');
      expect(start.height, lessThan(24), reason: 'width $width');
      // and the box is no taller than those two lines plus its padding
      final box = tester.getRect(find.byType(AgreedTermsBox));
      expect(box.height, lessThan(80), reason: 'width $width');
    }
  });

  test('formatDate falls back to the raw text for something that is not a date', () {
    expect(AgreedTermsBox.formatDate('soon'), 'soon');
  });

  group('the agreement comes through the shared models', () {
    test("MyApplicationModel reads the caregiver's own agreed salary and start date", () {
      final model = MyApplicationModel.fromJson({
        'status': 'accepted',
        'decided_by_admin': true,
        'agreed_salary': 800,
        'agreed_salary_unit': 'daily',
        'agreed_start_date': '2026-11-20',
      });
      expect(model.agreedSalary, 800);
      expect(model.agreedSalaryUnit, 'daily');
      expect(model.agreedStartDate, '2026-11-20');
    });

    test('both are null until the patient fills them in (and for older API responses)', () {
      final model = MyApplicationModel.fromJson({'status': 'accepted', 'decided_by_admin': true});
      expect(model.agreedSalary, isNull);
      expect(model.agreedSalaryUnit, isNull);
      expect(model.agreedStartDate, isNull);
    });
  });

  group('the caregiver\'s activity log records every salary / start date change by the family', () {
    MyApplicationModel app(List<Map<String, dynamic>> history) => MyApplicationModel.fromJson({
          'status': 'accepted',
          'decided_by_admin': false,
          'accepted_at': '2026-11-01T10:00:00Z',
          'applied_at': '2026-10-30T10:00:00Z',
          'agreement_history': history,
        });

    Future<void> pump(WidgetTester tester, MyApplicationModel a, {bool open = true}) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApplicationTimeline(a)))));
      if (open) {
        await tester.tap(find.text('Show Activity Log'));
        await tester.pump();
      }
    }

    testWidgets('lists "entered" then each "changed", with the amount and start date', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      expect(find.textContaining('Salary and start date entered by the family'), findsOneWidget);
      expect(find.textContaining('Salary and start date changed by the family'), findsOneWidget);
      expect(find.textContaining('₹30,000 per month, starts 1 Nov 2026'), findsOneWidget);
      expect(find.textContaining('₹1,200 per day, starts 26 Nov 2026'), findsOneWidget);
    });

    testWidgets('the whole log is shown in full, with a very thin separator between entries and no inner scrolling', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      // applied + accepted + two salary entries = 4 entries -> 3 separators
      for (final i in [1, 2, 3]) {
        expect(find.byKey(Key('timeline-separator-$i')), findsOneWidget, reason: 'separator $i');
      }
      expect(find.byKey(const Key('timeline-separator-0')), findsNothing);
      expect(find.byKey(const Key('timeline-separator-4')), findsNothing);
      expect(tester.widget<Divider>(find.byKey(const Key('timeline-separator-1'))).thickness, lessThanOrEqualTo(0.5));
      expect(find.descendant(of: find.byKey(const Key('application-timeline')), matching: find.byType(Scrollable)), findsNothing);
      // every line is on screen, none clipped by a fixed-height box
      for (final text in ['Applied by you', 'Accepted by employer', 'entered by the family', 'changed by the family']) {
        expect(find.textContaining(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('entries do not overlap: each starts below the end of the previous one', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      final rects = [
        tester.getRect(find.textContaining('changed by the family')),
        tester.getRect(find.textContaining('₹1,200 per day')),
        tester.getRect(find.textContaining('entered by the family')),
        tester.getRect(find.textContaining('₹30,000 per month')),
        tester.getRect(find.textContaining('Accepted by employer')),
        tester.getRect(find.textContaining('Applied by you')),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom - 0.5), reason: 'line $i overlaps line ${i - 1}');
      }
    });

    testWidgets('the new salary and start date is its own bold line, so the change is easy to read', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
        {'salary': 1200, 'unit': 'daily', 'start_date': '2026-11-26', 'at': '2026-11-21T12:00:00Z'},
      ]));
      final detail = tester.widget<Text>(find.text('₹1,200 per day, starts 26 Nov 2026'));
      expect(detail.style!.fontWeight, FontWeight.bold);
    });

    testWidgets('the log is collapsed under "Show Activity Log" until tapped, and can be hidden again', (tester) async {
      await pump(tester, app([
        {'salary': 30000, 'unit': 'monthly', 'start_date': '2026-11-01', 'at': '2026-11-17T10:00:00Z'},
      ]), open: false);
      expect(find.text('Show Activity Log'), findsOneWidget);
      expect(find.textContaining('Accepted by employer'), findsNothing);
      expect(find.textContaining('Salary and start date'), findsNothing);
      expect(find.byKey(const Key('application-timeline')), findsNothing);

      await tester.tap(find.byKey(const Key('timeline-toggle')));
      await tester.pump();
      expect(find.text('Hide Activity Log'), findsOneWidget);
      expect(find.textContaining('Accepted by employer'), findsOneWidget);
      expect(find.textContaining('₹30,000 per month'), findsOneWidget);

      await tester.tap(find.byKey(const Key('timeline-toggle')));
      await tester.pump();
      expect(find.textContaining('Accepted by employer'), findsNothing);
      expect(find.text('Show Activity Log'), findsOneWidget);
    });

    testWidgets('with no history, no salary line (the rest of the log is unchanged)', (tester) async {
      await pump(tester, app(const []));
      expect(find.textContaining('Salary and start date'), findsNothing);
      expect(find.textContaining('Accepted by employer'), findsOneWidget);
    });
  });
}
