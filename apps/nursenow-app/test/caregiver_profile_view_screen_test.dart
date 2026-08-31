import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/features/caregiver_profile/screens/caregiver_profile_view_screen.dart';

CaregiverProfileModel _profile({String? selfiePhotoUrl}) => CaregiverProfileModel.fromJson({
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
    await tester.pumpWidget(
      MaterialApp(
        home: CaregiverProfileViewScreen(fetchProfile: () async => _profile()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nurse Nita'), findsWidgets);
    expect(find.text('NUR-500'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('34 yrs'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Registered Nurse below 2 years experience'), findsOneWidget);
    expect(find.text('Christian'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('Kannada'), findsOneWidget);
    // assigned counts as verified too, not just available.
    expect(find.text('VitaCare-verified caregiver'), findsOneWidget);
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
    await tester.pumpWidget(
      MaterialApp(
        home: CaregiverProfileViewScreen(fetchProfile: () async => _profile(selfiePhotoUrl: null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('shows the server error message on load failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CaregiverProfileViewScreen(
          fetchProfile: () async =>
              throw const ApiException(code: 'GEN_002', message: 'This applicant profile is not available.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This applicant profile is not available.'), findsOneWidget);
  });
}
