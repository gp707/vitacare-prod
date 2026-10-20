import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/patient_hospital/app/pinch_to_zoom_wrapper.dart';
import 'package:nursenow_app/patient_hospital/app/text_zoom_button.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/core/text_scale/text_scale_provider.dart';

Future<LocalStorage> _freshLocalStorage() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStorage.create();
}

void main() {
  group('TextScaleNotifier', () {
    test('starts at 1.15 (A+) when nothing has ever been saved — the default was bumped up a step from plain '
        'Normal, since most users skew older and the plain baseline read as too small', () async {
      final localStorage = await _freshLocalStorage();
      final notifier = TextScaleNotifier(localStorage);

      expect(notifier.state, 1.15);
    });

    test('starts at whatever was previously persisted, not the default', () async {
      SharedPreferences.setMockInitialValues({'text_scale': 1.3});
      final localStorage = await LocalStorage.create();
      final notifier = TextScaleNotifier(localStorage);

      expect(notifier.state, 1.3);
    });

    test('cycleNext steps Large (the new default) -> Extra Large -> Normal -> Large, persisting each step',
        () async {
      final localStorage = await _freshLocalStorage();
      final notifier = TextScaleNotifier(localStorage);

      await notifier.cycleNext();
      expect(notifier.state, 1.3);
      expect(localStorage.textScale, 1.3);

      await notifier.cycleNext();
      expect(notifier.state, 1.0);
      expect(localStorage.textScale, 1.0);

      await notifier.cycleNext();
      expect(notifier.state, 1.15);
      expect(localStorage.textScale, 1.15);
    });

    test('cycleNext from a mid-pinch value jumps to the next step strictly above it', () async {
      final localStorage = await _freshLocalStorage();
      final notifier = TextScaleNotifier(localStorage)..setContinuous(1.22);

      await notifier.cycleNext();

      expect(notifier.state, 1.3);
    });

    test('setContinuous clamps to the min/max bounds', () async {
      final localStorage = await _freshLocalStorage();
      final notifier = TextScaleNotifier(localStorage);

      notifier.setContinuous(0.4);
      expect(notifier.state, TextScaleLevels.min);

      notifier.setContinuous(5.0);
      expect(notifier.state, TextScaleLevels.max);
    });

    test('setContinuous does not persist by itself — only persist() does', () async {
      final localStorage = await _freshLocalStorage();
      final notifier = TextScaleNotifier(localStorage);

      notifier.setContinuous(1.3);
      expect(localStorage.textScale, 1.15);

      await notifier.persist();
      expect(localStorage.textScale, 1.3);
    });
  });

  group('TextZoomButton', () {
    Future<void> pump(WidgetTester tester, LocalStorage localStorage) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localStorageProvider.overrideWithValue(localStorage)],
          child: MaterialApp(
            home: Scaffold(appBar: AppBar(actions: const [TextZoomButton()])),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows A+ by default (the new bumped-up default), cycles to A++, then A, then back to A+',
        (tester) async {
      final localStorage = await _freshLocalStorage();
      await pump(tester, localStorage);

      expect(find.text('A+'), findsOneWidget);

      await tester.tap(find.byType(TextZoomButton));
      await tester.pumpAndSettle();
      expect(find.text('A++'), findsOneWidget);

      await tester.tap(find.byType(TextZoomButton));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      await tester.tap(find.byType(TextZoomButton));
      await tester.pumpAndSettle();
      expect(find.text('A+'), findsOneWidget);
    });

    testWidgets('persists the new level so it survives a fresh provider read', (tester) async {
      final localStorage = await _freshLocalStorage();
      await pump(tester, localStorage);

      await tester.tap(find.byType(TextZoomButton));
      await tester.pumpAndSettle();

      expect(localStorage.textScale, 1.3);
    });
  });

  group('PinchToZoomWrapper', () {
    Future<LocalStorage> pump(WidgetTester tester) async {
      final localStorage = await _freshLocalStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localStorageProvider.overrideWithValue(localStorage)],
          child: MaterialApp(
            home: PinchToZoomWrapper(
              child: Scaffold(
                body: ListView(children: const [SizedBox(height: 2000, child: Text('scrollable content'))]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return localStorage;
    }

    testWidgets('a two-finger pinch apart increases the scale, clamped to the max step', (tester) async {
      final localStorage = await pump(tester);
      final center = tester.getCenter(find.byType(Scaffold));

      final gesture1 = await tester.createGesture(pointer: 1);
      final gesture2 = await tester.createGesture(pointer: 2);
      await gesture1.down(center - const Offset(20, 0));
      await gesture2.down(center + const Offset(20, 0));
      await tester.pump();

      // Spread the two fingers far apart — well past a 1.3x distance ratio
      // — to prove the result still clamps at TextScaleLevels.max rather
      // than scaling without bound.
      await gesture1.moveTo(center - const Offset(200, 0));
      await gesture2.moveTo(center + const Offset(200, 0));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      expect(container.read(textScaleProvider), TextScaleLevels.max);

      await gesture1.up();
      await gesture2.up();
      await tester.pump();

      // Persisted once every finger lifts.
      expect(localStorage.textScale, TextScaleLevels.max);
    });

    testWidgets('a single-finger drag never touches the scale — ordinary scrolling is untouched', (tester) async {
      await pump(tester);

      final gesture = await tester.createGesture(pointer: 1);
      await gesture.down(tester.getCenter(find.byType(Scaffold)));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      expect(container.read(textScaleProvider), 1.15);
    });
  });
}
