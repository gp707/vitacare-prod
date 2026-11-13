import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_web/shared/widgets/admin_notes_dialog.dart';

Future<void> _open(WidgetTester tester, String? initial, List<String> saved) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showAdminNotesDialog(
            context,
            title: 'Notes · X',
            hint: 'type here',
            load: () async => initial,
            save: (n) async => saved.add(n),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('existing note is shown read-only, Edit then Save writes it', (tester) async {
    final saved = <String>[];
    await _open(tester, 'call after 5pm', saved);
    expect(find.text('call after 5pm'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new text');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, ['new text']);
    expect(find.text('new text'), findsOneWidget);
  });

  testWidgets('no note yet opens straight in the editor so one can be added', (tester) async {
    final saved = <String>[];
    await _open(tester, null, saved);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'first note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, ['first note']);
  });
}
