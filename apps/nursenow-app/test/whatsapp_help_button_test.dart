import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nursenow_app/app/whatsapp_help_button.dart';

void main() {
  testWidgets('tapping the button opens the WhatsApp deep link for the support number', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              WhatsAppHelpButton(
                launcher: (uri) async {
                  openedUri = uri;
                  return true;
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Click for Help'), findsOneWidget);
    await tester.tap(find.text('Click for Help'));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://wa.me/917259255869'));
  });

  testWidgets('shows a fallback snackbar when the launcher fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              WhatsAppHelpButton(launcher: (uri) async => false),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Click for Help'), findsOneWidget);
    await tester.tap(find.text('Click for Help'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open WhatsApp'), findsOneWidget);
  });
}
