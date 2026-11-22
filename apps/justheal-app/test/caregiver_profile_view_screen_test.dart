import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/caregiver_profile/screens/caregiver_profile_view_screen.dart';

// This screen embeds TextZoomButton (see WhatsAppHelpButton's own AppBar
// placement), a ConsumerWidget reading localStorageProvider — needs a real
// ProviderScope override, unlike the rest of this screen's own plain
// callback-driven content.
Future<void> _pump(WidgetTester tester, CaregiverProfileViewScreen screen) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(localStorage)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

CaregiverProfileModel _profile({String? selfiePhotoUrl, double? overallRating}) => CaregiverProfileModel.fromJson({
      'overall_rating': overallRating,
      'user_id': 'user-1',
      'profile_id': 'profile-1',
      'caregiver_number': 500,
      'full_name': 'Nurse Nita',
      'phone': '+919876543210',
      'email': 'nita@example.com',
      'gender': 'female',
      'age': 34,
      'selfie_photo_url': selfiePhotoUrl,
      'languages': ['hindi', 'kannada'],
      'highest_qualification': 'rn_below_2_years',
      'qualification_document_url': 'https://signed/qual.pdf',
      'aadhaar_document_url': 'https://signed/aadhaar.pdf',
      'other_document_urls': ['https://signed/other1.pdf'],
      'religion': 'christian',
      'terms_accepted': true,
      'verification_status': 'assigned',
      'preferred_cities': ['bangalore'],
      'created_at': '2026-08-01T10:00:00Z',
    });

void main() {
  testWidgets('shows the full profile once loaded — name, phone, age, gender, qualification, religion, languages',
      (tester) async {
    await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile()));

    expect(find.text('Nurse Nita'), findsWidgets);
    expect(find.text('NUR-500'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('34 yrs'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Registered Nurse below 2 years experience'), findsOneWidget);
    expect(find.text('Christian'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('Kannada'), findsOneWidget);
    // The "VitaCare-verified caregiver" badge was removed from the
    // product entirely — never shown regardless of verification_status.
    expect(find.text('VitaCare-verified caregiver'), findsNothing);
    expect(find.text('nita@example.com'), findsOneWidget);
    // Aadhaar/qualification/other documents and preferred cities are shown
    // in full, not trimmed. Job search preferences (duty type/min salary)
    // were removed from the product entirely — only preferred cities
    // remains, since admin-web still filters/displays it.
    expect(find.text('Aadhaar Card'), findsOneWidget);
    expect(find.text('Qualification Document'), findsOneWidget);
    expect(find.text('Other Document 1'), findsOneWidget);
    expect(find.text('View'), findsNWidgets(3));
    expect(find.text('Preferred Cities'), findsOneWidget);
    expect(find.text('Bangalore'), findsOneWidget);
  });

  testWidgets('shows a person icon placeholder when there is no selfie photo', (tester) async {
    await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile(selfiePhotoUrl: null)));

    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('shows the server error message on load failure', (tester) async {
    await _pump(
      tester,
      CaregiverProfileViewScreen(
        fetchProfile: () async =>
            throw const ApiException(code: 'GEN_002', message: 'This applicant profile is not available.'),
      ),
    );

    expect(find.text('This applicant profile is not available.'), findsOneWidget);
  });

  group('calling or messaging the nurse from her profile', () {
    testWidgets('shows a Call and a WhatsApp button once the profile has loaded', (tester) async {
      await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile()));
      expect(find.widgetWithText(FilledButton, 'Call'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
    });

    testWidgets('Call opens the dialer with her number', (tester) async {
      final launched = <Uri>[];
      await _pump(
        tester,
        CaregiverProfileViewScreen(
          fetchProfile: () async => _profile(),
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Call'));
      await tester.pump();
      expect(launched.single.toString(), 'tel:+919876543210');
    });

    testWidgets('WhatsApp opens a chat with her number, digits only and including the country code', (tester) async {
      final launched = <Uri>[];
      await _pump(
        tester,
        CaregiverProfileViewScreen(
          fetchProfile: () async => _profile(),
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'WhatsApp'));
      await tester.pump();
      expect(launched.single.toString(), 'https://wa.me/919876543210');
    });

    testWidgets('if the dialer cannot open, a banner shows the number to dial by hand', (tester) async {
      await _pump(
        tester,
        CaregiverProfileViewScreen(fetchProfile: () async => _profile(), launcher: (uri) async => false),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Call'));
      await tester.pump();
      expect(find.text('Could not open the dialer. Call +919876543210 directly.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('if WhatsApp is not installed, a banner says so and shows the number', (tester) async {
      await _pump(
        tester,
        CaregiverProfileViewScreen(
          fetchProfile: () async => _profile(),
          launcher: (uri) async => throw Exception('no whatsapp'),
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'WhatsApp'));
      await tester.pump();
      expect(find.text('Could not open WhatsApp. Message +919876543210 directly.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('no contact buttons while loading or when the profile fails to load', (tester) async {
      await _pump(
        tester,
        CaregiverProfileViewScreen(
          fetchProfile: () async => throw const ApiException(code: 'GEN_002', message: 'Not found'),
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Call'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsNothing);
    });
  });

  group('overall rating', () {
    testWidgets('a rated caregiver shows the stars in an arc over her picture and the number under it', (tester) async {
      await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile(overallRating: 4.5)));
      expect(find.byKey(const Key('rating-arc-avatar')), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_half), findsOneWidget);
      expect(find.text('Overall rating: 4.5 / 5'), findsOneWidget);
    });

    testWidgets('a caregiver at the 5 cap shows five full stars', (tester) async {
      await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile(overallRating: 5)));
      expect(find.byIcon(Icons.star), findsNWidgets(5));
      expect(find.text('Overall rating: 5.0 / 5'), findsOneWidget);
    });

    testWidgets('a caregiver nobody has rated still shows the arc, with empty stars and "Not rated yet"', (tester) async {
      await _pump(tester, CaregiverProfileViewScreen(fetchProfile: () async => _profile()));
      expect(find.byKey(const Key('rating-arc-avatar')), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text('Not rated yet'), findsOneWidget);
    });
  });
}
