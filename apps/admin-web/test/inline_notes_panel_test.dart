import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_web/shared/widgets/inline_notes_panel.dart';

void main() {
  Future<List<String>> pumpPanel(WidgetTester tester, {String? notes}) async {
    final saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineNotesPanel(subject: 'this patient', notes: notes, onSave: (n) async => saved.add(n)),
      ),
    ));
    return saved;
  }

  testWidgets('shows the saved note and no Save button until it is edited', (tester) async {
    await pumpPanel(tester, notes: 'Calls after 6pm');
    expect(find.text('Calls after 6pm'), findsOneWidget);
    expect(find.byKey(const Key('inline-notes-save')), findsNothing);
  });

  testWidgets('Save asks for confirmation, then saves the edited note', (tester) async {
    final saved = await pumpPanel(tester, notes: 'old');
    await tester.enterText(find.byKey(const Key('inline-notes-field')), 'new note');
    await tester.pump();
    await tester.tap(find.byKey(const Key('inline-notes-save')));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('Save note?'), findsOneWidget);
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(saved, ['new note']);
  });

  testWidgets('declining the confirmation saves nothing', (tester) async {
    final saved = await pumpPanel(tester, notes: 'old');
    await tester.enterText(find.byKey(const Key('inline-notes-field')), 'new note');
    await tester.pump();
    await tester.tap(find.byKey(const Key('inline-notes-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('Cancel puts the saved note back', (tester) async {
    await pumpPanel(tester, notes: 'old');
    await tester.enterText(find.byKey(const Key('inline-notes-field')), 'typing');
    await tester.pump();
    await tester.tap(find.byKey(const Key('inline-notes-cancel')));
    await tester.pump();
    expect(find.text('old'), findsOneWidget);
    expect(find.byKey(const Key('inline-notes-save')), findsNothing);
  });

  testWidgets('wide rows put the panel in the right column, narrow rows below', (tester) async {
    Widget layout() => const MaterialApp(
        home: Scaffold(body: NotesSideLayout(main: Text('main'), panel: Text('panel'))));
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpWidget(layout());
    expect(tester.getTopLeft(find.text('panel')).dx, greaterThan(tester.getTopLeft(find.text('main')).dx));
    expect(tester.getTopLeft(find.text('panel')).dy, tester.getTopLeft(find.text('main')).dy);
    await tester.binding.setSurfaceSize(const Size(500, 600));
    await tester.pumpWidget(layout());
    expect(tester.getTopLeft(find.text('panel')).dy, greaterThan(tester.getTopLeft(find.text('main')).dy));
    await tester.binding.setSurfaceSize(null);
  });
}
