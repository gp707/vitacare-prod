import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/app/app.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';

void main() {
  testWidgets('with no stored session, RootScreen routes to Login',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageProvider.overrideWithValue(localStorage)],
        child: const AdminWebApp(),
      ),
    );

    // RootScreen briefly shows a loading indicator, then loadSession() finds
    // no token and navigates to /login without any network call.
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
  });
}
