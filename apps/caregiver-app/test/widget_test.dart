import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caregiver_app/app/app.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';

void main() {
  testWidgets('with no stored session, Splash routes to Login', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(localStorage)],
        child: const CaregiverApp(),
      ),
    );

    // Splash briefly shows the logo, then loadSession() finds no token and
    // navigates to /login without any network call.
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('New here? Register'), findsOneWidget);
  });
}
