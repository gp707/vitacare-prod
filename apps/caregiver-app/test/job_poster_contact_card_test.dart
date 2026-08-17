import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/features/jobs/widgets/job_poster_contact_card.dart';

void main() {
  const poster = JobPosterModel(fullName: 'Admin Kumar', phone: '+919876500000');

  testWidgets('shows the poster\'s name and phone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: JobPosterContactCard(poster: poster))),
    );

    expect(find.text('Admin Kumar'), findsOneWidget);
    expect(find.text('+919876500000'), findsOneWidget);
  });

  testWidgets('tapping Call opens a tel: link with the poster\'s phone number', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobPosterContactCard(
            poster: poster,
            launcher: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Call'));
    await tester.pumpAndSettle();

    expect(openedUri, Uri(scheme: 'tel', path: '+919876500000'));
  });

  testWidgets('tapping WhatsApp opens a wa.me link with digits only', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobPosterContactCard(
            poster: poster,
            launcher: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'WhatsApp'));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://wa.me/919876500000'));
  });

  testWidgets('shows a fallback snackbar when the launcher fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobPosterContactCard(poster: poster, launcher: (uri) async => false),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Call'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the dialer'), findsOneWidget);
  });
}
