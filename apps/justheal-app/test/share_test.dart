import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/share/share_app_card.dart';
import 'package:nursenow_app/share/share_messages.dart';
import 'package:nursenow_app/share/share_service.dart';

JobModel _job({String? salary = '1100', String frequency = 'daily'}) => JobModel.fromJson({
      'id': 'job-1',
      'city': 'bangalore',
      'area': 'Indiranagar, near 12th Main',
      'duty_type': 'day_duty',
      'frequency_of_care': frequency,
      'salary_amount': salary,
      'status': 'active',
      'posted_by': 'patient-1',
      'languages': ['hindi'],
      'start_date': '2026-12-01',
      'created_at': '2026-11-01T10:00:00Z',
      'posted_at': '2026-11-01T10:00:00Z',
      'patient_job_number': 548,
    });

void main() {
  group('messages', () {
    test('the store link carries the audience and what was shared, and nothing personal', () {
      final link = appStoreLink(audience: ShareAudience.caregiver);
      expect(link, startsWith('https://play.google.com/store/apps/details?id=in.vitacasahealth.justheal'));
      expect(Uri.parse(link).queryParameters['referrer'], 'utm_source=share&utm_medium=app_invite&utm_campaign=caregiver');
      expect(Uri.parse(appStoreLink(audience: ShareAudience.individual, medium: 'job_share')).queryParameters['referrer'],
          'utm_source=share&utm_medium=job_share&utm_campaign=individual');
    });

    test('each audience gets its own wording and the link', () {
      final caregiver = appInviteMessage(ShareAudience.caregiver);
      final family = appInviteMessage(ShareAudience.individual);
      final org = appInviteMessage(ShareAudience.organisation);
      expect(caregiver, contains('jobs'));
      expect(family, contains('families find caregivers'));
      expect(org, contains('hospital, clinic or rehab'));
      for (final m in [caregiver, family, org]) {
        expect(m, contains('https://play.google.com/store/apps/details?id=in.vitacasahealth.justheal'));
      }
      expect({caregiver, family, org}.length, 3);
    });

    test('a job share has the shift, city and plain salary, but never the area, a name or a phone number', () {
      final m = jobShareMessage(_job());
      expect(m, contains('12Hrs Day Shift (8am to 8pm) in Bangalore'));
      expect(m, contains('₹1,100 per day'));
      expect(m, isNot(contains('Indiranagar')));
      expect(m, isNot(contains('+91')));
      expect(Uri.parse(RegExp(r'https://\S+').firstMatch(m)!.group(0)!).queryParameters['referrer'], contains('utm_medium=job_share'));
    });

    test('a monthly rate reads per month, and a salary that is a sentence is left out', () {
      expect(jobShareMessage(_job(salary: '30000', frequency: 'monthly')), contains('₹30,000 per month'));
      final text = jobShareMessage(_job(salary: '26000 pm/867 per day\nTo\n30000 pm/1000 per day'));
      expect(text, isNot(contains('₹')));
      expect(jobShareMessage(_job(salary: null)), isNot(contains('₹')));
    });

    test('WhatsApp gets the whole message, safely encoded', () {
      final uri = whatsAppShareUri('Hello & welcome: 50% off?');
      expect(uri.host, 'wa.me');
      expect(uri.queryParameters['text'], 'Hello & welcome: 50% off?');
    });
  });

  group('ShareAppCard', () {
    late List<Uri> opened;
    late List<String> shared;

    Future<void> pump(
      WidgetTester tester, {
      ShareAudience audience = ShareAudience.caregiver,
      bool compact = false,
      Future<bool> Function(Uri)? launcher,
      Future<void> Function(String)? sheet,
    }) async {
      opened = [];
      shared = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shareUrlLauncherProvider.overrideWithValue(launcher ??
                (uri) async {
                  opened.add(uri);
                  return true;
                }),
            shareSheetProvider.overrideWithValue(sheet ??
                (text) async {
                  shared.add(text);
                }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ShareAppCard(audience: audience, flow: 'caregiver', screen: 'profile', compact: compact),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('asks the right question for each audience', (tester) async {
      await pump(tester);
      expect(find.text('Know a nurse or caregiver looking for work?'), findsOneWidget);
      await pump(tester, audience: ShareAudience.individual);
      expect(find.text('Know a family that needs a nurse or caregiver?'), findsOneWidget);
      await pump(tester, audience: ShareAudience.organisation);
      expect(find.text('Know a hospital or clinic that is hiring?'), findsOneWidget);
    });

    testWidgets('Share on WhatsApp opens WhatsApp with the invite already typed — one tap', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('share-app-whatsapp')));
      await tester.pump();
      expect(opened.single.host, 'wa.me');
      expect(opened.single.queryParameters['text'], appInviteMessage(ShareAudience.caregiver));
      expect(shared, isEmpty);
    });

    testWidgets('More opens the general share sheet with the same message', (tester) async {
      await pump(tester, audience: ShareAudience.individual);
      await tester.tap(find.byKey(const Key('share-app-more')));
      await tester.pump();
      expect(shared.single, appInviteMessage(ShareAudience.individual));
      expect(opened, isEmpty);
    });

    testWidgets('if WhatsApp cannot be opened it falls back to the share sheet', (tester) async {
      await pump(tester, launcher: (uri) async => false);
      await tester.tap(find.byKey(const Key('share-app-whatsapp')));
      await tester.pump();
      expect(shared.single, appInviteMessage(ShareAudience.caregiver));
    });

    testWidgets('a launcher that throws is handled the same way', (tester) async {
      await pump(tester, launcher: (uri) async => throw Exception('no whatsapp'));
      await tester.tap(find.byKey(const Key('share-app-whatsapp')));
      await tester.pump();
      expect(shared, hasLength(1));
    });

    testWidgets('if nothing can share, a message is shown instead of failing silently', (tester) async {
      await pump(tester, sheet: (text) async => throw Exception('no share'));
      await tester.tap(find.byKey(const Key('share-app-more')));
      await tester.pump();
      expect(find.text('Could not open sharing. Please try again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('the compact version drops the explanation but keeps both buttons', (tester) async {
      await pump(tester, compact: true);
      expect(find.text('Share JustHeal with them. It takes two taps.'), findsNothing);
      expect(find.byKey(const Key('share-app-whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('share-app-more')), findsOneWidget);
    });
  });

  group('ShareJobButton', () {
    testWidgets('sends the given job message straight to WhatsApp', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shareUrlLauncherProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(body: ShareJobButton(message: jobShareMessage(_job()), screen: 'jobs')),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('share-job')));
      await tester.pump();
      expect(opened.single.queryParameters['text'], jobShareMessage(_job()));
    });
  });
}
