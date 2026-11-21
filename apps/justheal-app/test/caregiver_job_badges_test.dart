import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/features/jobs/widgets/job_detail_card.dart';

Future<void> _pump(WidgetTester tester, Widget badge) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: badge))));
  await tester.pumpAndSettle();
}

// BlinkingStartDateBadge repeats its fade animation forever, so
// pumpAndSettle (which waits for animations to finish) never returns for
// it — bounded pumps instead, same reasoning other tests covering
// continuously-animating widgets elsewhere in this codebase already use.
Future<void> _pumpBlinking(WidgetTester tester, Widget badge) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: badge))));
  await tester.pump();
}

void main() {
  group('JobDetailCard header', () {
    JobModel jobWithStartDate() => JobModel.fromJson({
          'id': 'j1',
          'admin_job_number': 542,
          'city': 'bangalore',
          'area': 'Whitefield',
          'duty_type': 'live_in',
          'frequency_of_care': 'daily',
          'start_date': '2027-01-25',
          'languages': ['hindi'],
          'salary_amount': '867',
          'status': 'active',
          'posted_by': 'admin-1',
          'posted_at': '2026-11-14T10:00:00Z',
          'created_at': '2026-11-14T10:00:00Z',
        });

    testWidgets('does not show the start date, and the salary takes the whole row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: JobDetailCard(job: jobWithStartDate())))),
      ));
      await tester.pump();

      expect(find.byType(BlinkingStartDateBadge), findsNothing);
      expect(find.textContaining('Start '), findsNothing);
      // 390 wide minus 16 padding on each side = 358 for the row.
      expect(tester.getSize(find.byType(SalaryBadge)).width, closeTo(358, 1));
    });
  });

  group('JobDetailCard sharing', () {
    JobModel job() => JobModel.fromJson({
          'id': 'j1',
          'patient_job_number': 548,
          'city': 'bangalore',
          'area': 'Whitefield',
          'duty_type': 'day_duty',
          'frequency_of_care': 'daily',
          'salary_amount': '1100',
          'languages': ['hindi'],
          'status': 'active',
          'posted_by': 'patient-1',
          'posted_at': '2026-11-14T10:00:00Z',
          'created_at': '2026-11-14T10:00:00Z',
        });

    Future<void> pumpCard(WidgetTester tester, {required bool showShare}) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: JobDetailCard(job: job(), showShare: showShare))),
        ),
      ));
      await tester.pump();
    }

    testWidgets('the browse list shows "Share this job on WhatsApp"', (tester) async {
      await pumpCard(tester, showShare: true);
      expect(find.byKey(const Key('share-job')), findsOneWidget);
      expect(find.text('Share this job on WhatsApp'), findsOneWidget);
    });

    testWidgets('it is not shown by default (for example once the caregiver is already on the job)', (tester) async {
      await pumpCard(tester, showShare: false);
      expect(find.byKey(const Key('share-job')), findsNothing);
    });
  });

  group('SalaryBadge', () {
    testWidgets('has no calendar icon and shows the amount, tappable to a full-detail popup', (tester) async {
      await _pump(tester, const SalaryBadge(amount: '26000', frequencyOfCare: 'monthly'));

      expect(find.text('26000'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('₹26000 (Monthly)'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a daily rate\'s popup names the frequency too', (tester) async {
      await _pump(tester, const SalaryBadge(amount: '867', frequencyOfCare: 'daily'));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('₹867 (Daily)'), findsOneWidget);
    });
  });

  group('BlinkingStartDateBadge', () {
    testWidgets('has no calendar icon, shows a single-space "Start" label (no colon), tappable to a popup',
        (tester) async {
      await _pumpBlinking(tester, const BlinkingStartDateBadge(label: 'Start 25/12/26'));

      expect(find.text('Start 25/12/26'), findsOneWidget);
      expect(find.text('Start: 25/12/26'), findsNothing);
      expect(find.byIcon(Icons.calendar_today), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // flush the dialog's own entry transition

      expect(find.text('Preferred Start Date'), findsOneWidget);
      // The full label appears twice once the dialog is open — once on the
      // (still-mounted) badge behind it, once in the dialog content.
      expect(find.text('Start 25/12/26'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
