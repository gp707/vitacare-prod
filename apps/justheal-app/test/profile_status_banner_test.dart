import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/caregiver/features/profile/widgets/profile_status_banner.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

Future<void> _pump(WidgetTester tester, String status, {String? rejection, bool blink = false}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileStatusBanner(status: status, rejectionMessage: rejection, blink: blink)),
    ));

final _fade = find.descendant(of: find.byKey(const Key('profile-status-banner')), matching: find.byType(FadeTransition));

void main() {
  group('the profile status banner', () {
    testWidgets('is large and bold', (tester) async {
      await _pump(tester, VerificationStatus.assigned);
      final style = tester.widget<Text>(find.byKey(const Key('profile-status-text'))).style!;
      expect(style.fontSize, greaterThanOrEqualTo(20));
      expect(style.fontWeight!.index, greaterThanOrEqualTo(FontWeight.w700.index));
    });

    for (final c in [
      (VerificationStatus.assigned, 'Your profile is active.', AppColors.success),
      (VerificationStatus.unavailable, 'Your profile is inactive.', AppColors.warning),
      (VerificationStatus.pendingCall, "Your profile is under review. We'll notify you once verified.", AppColors.warning),
      (VerificationStatus.rejected, 'Your application was not approved. Contact the office for details.', AppColors.error),
    ]) {
      testWidgets('${c.$1}: shows "${c.$2}" in its own colour', (tester) async {
        await _pump(tester, c.$1);
        final text = tester.widget<Text>(find.byKey(const Key('profile-status-text')));
        expect(text.data, c.$2);
        expect(text.style!.color, c.$3);
      });
    }

    testWidgets('blinks: its opacity changes over time, and never settles', (tester) async {
      await _pump(tester, VerificationStatus.unavailable, blink: true);
      double opacity() => tester.widget<FadeTransition>(_fade).opacity.value;
      final seen = <double>{};
      for (var i = 0; i < 8; i++) {
        seen.add(double.parse(opacity().toStringAsFixed(2)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(seen.length, greaterThan(3), reason: 'opacity must keep changing');
      expect(seen.reduce((a, b) => a < b ? a : b), lessThan(0.6));
      expect(seen.reduce((a, b) => a > b ? a : b), greaterThan(0.8));
    });

    testWidgets('does not blink when switched off (steady text, used by tests)', (tester) async {
      await _pump(tester, VerificationStatus.assigned);
      expect(_fade, findsNothing);
    });
  });
}
