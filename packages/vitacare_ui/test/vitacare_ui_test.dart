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
}
