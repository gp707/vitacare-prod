import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

Future<void> _pump(WidgetTester tester, double? rating, {double radius = 40, double starSize = 20}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: VitaRatingArcAvatar(
            avatarRadius: radius,
            rating: rating,
            starSize: starSize,
            avatar: CircleAvatar(key: const Key('the-avatar'), radius: radius),
          ),
        ),
      ),
    ));

void main() {
  group('which stars are filled', () {
    test('rounds to the nearest half star, filling left to right', () {
      const f = Icons.star, h = Icons.star_half, e = Icons.star_border;
      expect(VitaRatingArcAvatar.starIcons(5), [f, f, f, f, f]);
      expect(VitaRatingArcAvatar.starIcons(4.5), [f, f, f, f, h]);
      expect(VitaRatingArcAvatar.starIcons(4.7), [f, f, f, f, h]); // 4.7 -> 4.5
      expect(VitaRatingArcAvatar.starIcons(4.8), [f, f, f, f, f]); // 4.8 -> 5
      expect(VitaRatingArcAvatar.starIcons(2.5), [f, f, h, e, e]);
      expect(VitaRatingArcAvatar.starIcons(1), [f, e, e, e, e]);
      expect(VitaRatingArcAvatar.starIcons(0), [e, e, e, e, e]);
    });

    test('a rating outside 0-5 is clamped', () {
      expect(VitaRatingArcAvatar.starIcons(9), VitaRatingArcAvatar.starIcons(5));
      expect(VitaRatingArcAvatar.starIcons(-3), VitaRatingArcAvatar.starIcons(0));
    });
  });

  group('the arc', () {
    testWidgets('no rating: just the picture, no stars at all', (tester) async {
      await _pump(tester, null);
      expect(find.byKey(const Key('the-avatar')), findsOneWidget);
      expect(find.byKey(const Key('rating-arc-avatar')), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('draws five stars with the right fill, and the picture stays', (tester) async {
      await _pump(tester, 4.5);
      expect(find.byKey(const Key('the-avatar')), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_half), findsNWidgets(1));
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('the stars sit in a half circle over the top of the picture, left to right', (tester) async {
      await _pump(tester, 5);
      final avatar = tester.getRect(find.byKey(const Key('the-avatar')));
      final centres = [for (var i = 0; i < 5; i++) tester.getCenter(find.byKey(Key('rating-arc-star-$i')))];
      // left to right
      for (var i = 1; i < 5; i++) {
        expect(centres[i].dx, greaterThan(centres[i - 1].dx), reason: 'star $i is right of star ${i - 1}');
      }
      // the middle star is the highest one; the ends are lowest (an arch)
      expect(centres[2].dy, lessThan(centres[1].dy));
      expect(centres[2].dy, lessThan(centres[3].dy));
      expect(centres[1].dy, lessThan(centres[0].dy));
      expect(centres[3].dy, lessThan(centres[4].dy));
      // symmetric around the picture's centre
      expect(centres[2].dx, closeTo(avatar.center.dx, 0.5));
      expect(centres[0].dx - avatar.center.dx, closeTo(-(centres[4].dx - avatar.center.dx), 0.5));
      // the arc is over the picture, never over its lower half: no star below the picture's centre line
      for (final c in centres) {
        expect(c.dy, lessThanOrEqualTo(avatar.center.dy + 0.5));
      }
      // and every star is outside the circle itself, not covering the face
      for (final c in centres) {
        expect((c - avatar.center).distance, greaterThan(avatar.width / 2));
      }
    });

    testWidgets('says the rating to a screen reader', (tester) async {
      await _pump(tester, 4.5);
      expect(find.bySemanticsLabel('Rated 4.5 out of 5'), findsOneWidget);
    });
  });
}
