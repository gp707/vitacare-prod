import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/app_versions/data/app_versions_repository.dart';
import 'package:admin_web/features/app_versions/screens/app_versions_screen.dart';

AppMinVersion _version({
  String platform = 'android',
  String minVersion = '1.0.0',
  String? storeUrl,
  String? updateMessage,
  String? updatedByName,
}) {
  return AppMinVersion.fromJson({
    'platform': platform,
    'min_version': minVersion,
    'store_url': storeUrl,
    'update_message': updateMessage,
    'updated_by_name': updatedByName,
    'updated_at': '2026-08-17T10:00:00Z',
  });
}

class _FakeAppVersionsRepository extends AppVersionsRepository {
  List<AppMinVersion> versions;
  String? updatedPlatform;
  String? updatedMinVersion;
  String? updatedStoreUrl;

  _FakeAppVersionsRepository(this.versions) : super(Dio());

  @override
  Future<List<AppMinVersion>> list() async => versions;

  @override
  Future<void> update(String platform, {required String minVersion, String? storeUrl, String? updateMessage}) async {
    updatedPlatform = platform;
    updatedMinVersion = minVersion;
    updatedStoreUrl = storeUrl;
    versions = versions
        .map((v) => v.platform == platform
            ? _version(platform: platform, minVersion: minVersion, storeUrl: storeUrl, updatedByName: 'Test Admin')
            : v)
        .toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeAppVersionsRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        appVersionsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AppVersionsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists both platforms with their current minimum version', (tester) async {
    final repo = _FakeAppVersionsRepository([
      _version(platform: 'android', minVersion: '1.2.0'),
      _version(platform: 'ios', minVersion: '1.1.0'),
    ]);
    await _pump(tester, repo);

    expect(find.text('Minimum version: 1.2.0'), findsOneWidget);
    expect(find.text('Minimum version: 1.1.0'), findsOneWidget);
  });

  testWidgets('editing a platform pre-fills the current values and saves via the repository', (tester) async {
    final repo = _FakeAppVersionsRepository([
      _version(
        platform: 'android',
        minVersion: '1.2.0',
        storeUrl: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
      ),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    final minVersionField = find.widgetWithText(TextField, 'Minimum version (e.g. 1.2.0)');
    expect(
      tester.widget<TextField>(minVersionField).controller!.text,
      '1.2.0',
    );

    await tester.enterText(minVersionField, '1.3.0');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.updatedPlatform, 'android');
    expect(repo.updatedMinVersion, '1.3.0');
    expect(find.text('Minimum version: 1.3.0'), findsOneWidget);
  });

  testWidgets('shows who last updated a platform when known', (tester) async {
    final repo = _FakeAppVersionsRepository([
      _version(platform: 'android', minVersion: '1.2.0', updatedByName: 'Priya Admin'),
    ]);
    await _pump(tester, repo);

    expect(find.text('Last updated by Priya Admin'), findsOneWidget);
  });
}
