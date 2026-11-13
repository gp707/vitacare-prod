import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_web/shared/widgets/action_help.dart';

void main() {
  testWidgets('hovering a button shows what it will do', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ActionHelp(
            message: JobActionHelp.remind,
            child: TextButton(onPressed: () {}, child: const Text('Remind')),
          ),
        ),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Remind')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('cannot be taken back'), findsOneWidget);
  });

  test('Edit warns when saving would approve or reopen', () {
    expect(JobActionHelp.edit(pendingReview: true, closed: false), contains('APPROVES'));
    expect(JobActionHelp.edit(pendingReview: false, closed: true), contains('REOPENS'));
    expect(JobActionHelp.edit(pendingReview: false, closed: false), contains('no new-job notification'));
  });
}
