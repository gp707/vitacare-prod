import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caregiver_app/app/update_required_screen.dart';

void main() {
  testWidgets('shows a generic message and no button when no store_url is configured', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UpdateRequiredScreen()));

    expect(find.text('Update Required'), findsOneWidget);
    expect(find.textContaining('A new version of NurseJobs is available'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Update Now'), findsNothing);
  });

  testWidgets('shows the admin-configured message when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UpdateRequiredScreen(
          storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
          message: 'Critical security update — please update now.',
        ),
      ),
    );

    expect(find.text('Critical security update — please update now.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Update Now'), findsOneWidget);
  });

  testWidgets('tapping Update Now opens the store_url', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateRequiredScreen(
          storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
          launcher: (uri) async {
            openedUri = uri;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Now'));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs'));
  });

  testWidgets('shows a fallback snackbar when the launcher fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateRequiredScreen(
          storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
          launcher: (uri) async => false,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the app store'), findsOneWidget);
  });
}
