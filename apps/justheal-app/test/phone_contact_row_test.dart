import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nursenow_app/patient_hospital/features/individual/widgets/call_tap.dart';

Future<List<Uri>> _pump(WidgetTester tester, {Future<bool> Function(Uri)? launcher}) async {
  final launched = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        phoneLauncherProvider.overrideWithValue(launcher ??
            (uri) async {
              launched.add(uri);
              return true;
            }),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: PhoneContactRow(phone: '+919876543210', name: 'Asha'))),
      ),
    ),
  );
  return launched;
}

void main() {
  testWidgets('shows the number and a WhatsApp chip', (tester) async {
    await _pump(tester);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('the number is a button: a pill with a call icon, next to the WhatsApp pill', (tester) async {
    await _pump(tester);
    final pill = tester.widget<Container>(find.byKey(const Key('call-button')));
    final decoration = pill.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.borderRadius, isNotNull);
    expect(find.descendant(of: find.byKey(const Key('call-button')), matching: find.byIcon(Icons.call)), findsOneWidget);
    expect(find.byKey(const Key('whatsapp-tap')), findsOneWidget);
  });

  testWidgets('tapping the number opens the dialer', (tester) async {
    final launched = await _pump(tester);
    await tester.tap(find.text('+919876543210'));
    await tester.pump();
    expect(launched.single.toString(), 'tel:+919876543210');
  });

  testWidgets('tapping WhatsApp opens a chat with the number, digits only and with the country code', (tester) async {
    final launched = await _pump(tester);
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(launched.single.toString(), 'https://wa.me/919876543210');
  });

  testWidgets('if WhatsApp cannot be opened a banner shows the number to message by hand', (tester) async {
    await _pump(tester, launcher: (uri) async => false);
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(find.text('Could not open WhatsApp. Message +919876543210 directly.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a launcher that throws is handled the same way', (tester) async {
    await _pump(tester, launcher: (uri) async => throw Exception('no whatsapp'));
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(find.text('Could not open WhatsApp. Message +919876543210 directly.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

}
