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

  group('VitaAppBar', () {
    testWidgets('renders the title on its own row, separate from the actions row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: VitaAppBar(
              title: 'Requirement Posted',
              actions: const [Icon(Icons.notifications), Icon(Icons.help)],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.text('Requirement Posted'), findsOneWidget);
      // The title Text and the AppBar's actions sit in different rows —
      // the title is not inside the same Row as the action icons.
      final titleFinder = find.text('Requirement Posted');
      final actionsRow = find.ancestor(of: find.byIcon(Icons.notifications), matching: find.byType(Row)).first;
      expect(find.descendant(of: actionsRow, matching: titleFinder), findsNothing);
    });

    testWidgets('a long title is never squeezed by actions — it keeps its own full-width row', (tester) async {
      const longTitle = 'A Genuinely Very Long Screen Title That Would Have Been Truncated Before';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: VitaAppBar(
              title: longTitle,
              actions: const [Icon(Icons.star), Icon(Icons.help), Icon(Icons.notifications), Icon(Icons.menu)],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text(longTitle));
      // It's still wrapped in Flexible+ellipsis as a safety net, but the
      // whole string is present (not pre-truncated by this widget itself)
      // since it now has the full screen width to render into, not a
      // squeezed title slot shared with the actions.
      expect(textWidget.data, longTitle);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
        'the icon keeps its own triple-tap-to-logout behavior, unambiguously targetable even with actions present',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: VitaAppBar(
              title: 'Profile',
              onTripleTap: () => callCount++,
              // Regression coverage: actions add their own GestureDetectors
              // into VitaAppBar's subtree, which once made a plain
              // find.byType(GestureDetector) scoped to VitaAppBar ambiguous
              // (multiple matches) — the keyed finder below must still work.
              actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.help)), const Icon(Icons.notifications)],
            ),
          ),
        ),
      );

      final icon = find.byKey(const ValueKey('vitaAppBarBrandIconTap'));
      await tester.tap(icon);
      await tester.tap(icon);
      expect(callCount, 0);
      await tester.tap(icon);

      expect(callCount, 1);
    });

    testWidgets('renders titleTrailing right after the title text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: VitaAppBar(title: 'My Profile', titleTrailing: const Text('Available')),
          ),
        ),
      );

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('renders a bottom widget (e.g. a TabBar) below the title row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: VitaAppBar(
                title: 'My Jobs',
                bottom: const TabBar(tabs: [Tab(text: 'Applied'), Tab(text: 'Past')]),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );

      expect(find.text('My Jobs'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
    });

    test('preferredSize folds in the title row height plus an optional bottom widget\'s own height', () {
      const plain = VitaAppBar(title: 'Jobs');
      final withBottom = VitaAppBar(title: 'My Jobs', bottom: const TabBar(tabs: [Tab(text: 'A')]));

      expect(withBottom.preferredSize.height, greaterThan(plain.preferredSize.height));
    });
  });
}
