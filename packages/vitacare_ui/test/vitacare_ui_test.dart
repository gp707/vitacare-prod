import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

void main() {
  testWidgets('VitaStatusBadge renders the label for a known status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VitaStatusBadge(status: VerificationStatus.available)),
      ),
    );
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('VitaStatusBadge falls back to the raw status for an unknown value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VitaStatusBadge(status: 'something_new'))),
    );
    expect(find.text('something_new'), findsOneWidget);
  });

  testWidgets('VitaMultiSelectChips toggles selection on tap', (tester) async {
    List<String> selected = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return VitaMultiSelectChips(
                options: Language.all,
                labels: Language.displayNames,
                selected: selected,
                onChanged: (next) => setState(() => selected = next),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Hindi'), findsOneWidget);
    await tester.tap(find.text('Hindi'));
    await tester.pump();
    expect(selected, contains('hindi'));
  });

  testWidgets('VitaLoadingIndicator renders a spinner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VitaLoadingIndicator())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('VitaOfflineBanner shows the offline message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VitaOfflineBanner())));
    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  group('showVitaErrorBanner', () {
    Widget buildApp(void Function(BuildContext) onPressed) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => onPressed(context),
                child: const Text('Trigger'),
              ),
            ),
          ),
        );

    testWidgets('shows the message in a red MaterialBanner', (tester) async {
      await tester.pumpWidget(buildApp((context) => showVitaErrorBanner(context, 'Failed to save')));
      await tester.tap(find.text('Trigger'));
      await tester.pump();

      expect(find.text('Failed to save'), findsOneWidget);
      final banner = tester.widget<MaterialBanner>(find.byType(MaterialBanner));
      expect(banner.backgroundColor, AppColors.error);

      // Drain the still-pending 5s auto-dismiss timer so the test doesn't
      // end with a live Timer outliving the widget tree.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('tapping the close button dismisses it immediately', (tester) async {
      await tester.pumpWidget(buildApp((context) => showVitaErrorBanner(context, 'Failed to save')));
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsNothing);

      // The auto-dismiss timer is still scheduled (hideCurrentMaterialBanner
      // is a safe no-op the second time) — drain it before the test ends.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('auto-dismisses after 5 seconds', (tester) async {
      await tester.pumpWidget(buildApp((context) => showVitaErrorBanner(context, 'Failed to save')));
      await tester.tap(find.text('Trigger'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('showing a second banner replaces the first, not stacks it', (tester) async {
      await tester.pumpWidget(buildApp((context) {
        showVitaErrorBanner(context, 'First error');
        showVitaErrorBanner(context, 'Second error');
      }));
      await tester.tap(find.text('Trigger'));
      await tester.pump();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('Second error'), findsOneWidget);
      expect(find.text('First error'), findsNothing);

      // Two timers are pending (one per call) — drain both before the test
      // ends.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('VitaAppBarTitle', () {
    testWidgets('with no onTripleTap (the default), the icon is a plain static image — no tap handling at all',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(appBar: AppBar(title: const VitaAppBarTitle('Title')))),
      );

      expect(find.text('Title'), findsOneWidget);
      expect(find.descendant(of: find.byType(VitaAppBarTitle), matching: find.byType(GestureDetector)),
          findsNothing);
    });

    testWidgets('3 taps within the window fires onTripleTap exactly once', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(title: VitaAppBarTitle('Title', onTripleTap: () => callCount++))),
        ),
      );

      final icon = find.descendant(of: find.byType(VitaAppBarTitle), matching: find.byType(GestureDetector));
      await tester.tap(icon);
      await tester.tap(icon);
      expect(callCount, 0);
      await tester.tap(icon);

      expect(callCount, 1);
    });

    testWidgets('only 2 taps never fires it', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(title: VitaAppBarTitle('Title', onTripleTap: () => callCount++))),
        ),
      );

      final icon = find.descendant(of: find.byType(VitaAppBarTitle), matching: find.byType(GestureDetector));
      await tester.tap(icon);
      await tester.tap(icon);

      expect(callCount, 0);
    });

    testWidgets('a 4th tap right after a completed triple-tap starts counting fresh, not firing again immediately',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(title: VitaAppBarTitle('Title', onTripleTap: () => callCount++))),
        ),
      );

      final icon = find.descendant(of: find.byType(VitaAppBarTitle), matching: find.byType(GestureDetector));
      await tester.tap(icon);
      await tester.tap(icon);
      await tester.tap(icon);
      expect(callCount, 1);

      await tester.tap(icon);
      expect(callCount, 1);
    });

    testWidgets('a gap longer than the window resets the count — 2 taps, a pause, then 2 more never fires it',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: VitaAppBarTitle(
                'Title',
                onTripleTap: () => callCount++,
                tripleTapWindow: const Duration(milliseconds: 100),
              ),
            ),
          ),
        ),
      );
      final icon = find.descendant(of: find.byType(VitaAppBarTitle), matching: find.byType(GestureDetector));

      await tester.runAsync(() async {
        await tester.tap(icon);
        await tester.tap(icon);
        // Real wall-clock wait past the 100ms window — _handleTap compares
        // against DateTime.now(), which FakeAsync's virtual time doesn't
        // advance, so this needs a genuine delay via runAsync.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.tap(icon);
        await tester.tap(icon);
      });

      // The post-gap pair only reaches a count of 2 (reset, then +1, +1),
      // never the 3 needed to fire — proves the gap genuinely resets state
      // rather than the count just accumulating indefinitely.
      expect(callCount, 0);
    });
  });
}
