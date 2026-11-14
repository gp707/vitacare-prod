import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_web/shared/widgets/sort_bar.dart';

void main() {
  group('nextSort', () {
    test('tapping the active column flips its direction', () {
      expect(nextSort(currentKey: 'full_name', currentAscending: true, tappedKey: 'full_name'),
          ('full_name', false));
      expect(nextSort(currentKey: 'full_name', currentAscending: false, tappedKey: 'full_name'),
          ('full_name', true));
    });

    test('a new column starts ascending, but registration date starts newest first', () {
      expect(nextSort(currentKey: 'created_at', currentAscending: false, tappedKey: 'phone'),
          ('phone', true));
      expect(nextSort(currentKey: 'phone', currentAscending: true, tappedKey: 'created_at'),
          ('created_at', false));
    });
  });

  group('SortBar', () {
    Future<List<(String, bool)>> pump(WidgetTester tester, {String key = 'created_at', bool asc = false}) async {
      final calls = <(String, bool)>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SortBar(
            options: const [SortOption('created_at', 'Registered'), SortOption('full_name', 'Name')],
            sortKey: key,
            ascending: asc,
            onChanged: (k, a) => calls.add((k, a)),
          ),
        ),
      ));
      return calls;
    }

    testWidgets('the direction button flips the current sort', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.byKey(const Key('sort-bar-direction')));
      expect(calls, [('created_at', true)]);
    });

    testWidgets('choosing another column starts from that column\'s natural order', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.byKey(const Key('sort-bar-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      expect(calls, [('full_name', true)]);
    });
  });
}
