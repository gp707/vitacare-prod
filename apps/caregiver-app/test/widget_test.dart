import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caregiver_app/app/app.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/core/version/app_version_repository.dart';

class _FakeAppVersionRepository extends AppVersionRepository {
  _FakeAppVersionRepository() : super(Dio());

  @override
  Future<UpdateRequiredInfo?> checkForUpdate() async => null;
}

void main() {
  testWidgets('with no stored session, Splash routes to Login', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          appVersionRepositoryProvider.overrideWithValue(_FakeAppVersionRepository()),
        ],
        child: const CaregiverApp(),
      ),
    );

    // Splash briefly shows the logo, then the version check reports no
    // update needed and loadSession() finds no token, navigating to /login.
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('New here? Register'), findsOneWidget);
  });
}
