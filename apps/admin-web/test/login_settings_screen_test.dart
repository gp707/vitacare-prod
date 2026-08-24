import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/login_settings/data/otp_settings_repository.dart';
import 'package:admin_web/features/login_settings/screens/login_settings_screen.dart';

OtpAppSetting _setting({
  String app = 'nursejobs',
  bool enabled = false,
  String? updatedByName,
}) {
  return OtpAppSetting.fromJson({
    'app': app,
    'enabled': enabled,
    'updated_by_name': updatedByName,
    'updated_at': '2026-08-24T10:00:00Z',
  });
}

class _FakeOtpSettingsRepository extends OtpSettingsRepository {
  List<OtpAppSetting> settings;
  String? updatedApp;
  bool? updatedEnabled;
  bool throwOnUpdate;

  _FakeOtpSettingsRepository(this.settings, {this.throwOnUpdate = false}) : super(Dio());

  @override
  Future<List<OtpAppSetting>> list() async => settings;

  @override
  Future<void> update(String app, bool enabled) async {
    updatedApp = app;
    updatedEnabled = enabled;
    if (throwOnUpdate) {
      throw ApiException(message: 'Something went wrong', code: 'GEN_003');
    }
    settings = settings
        .map((s) => s.app == app ? _setting(app: app, enabled: enabled, updatedByName: 'Test Admin') : s)
        .toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeOtpSettingsRepository repo) async {
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
        otpSettingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: LoginSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists both apps with their current state', (tester) async {
    final repo = _FakeOtpSettingsRepository([
      _setting(app: 'nursejobs', enabled: false),
      _setting(app: 'nursenow', enabled: true),
    ]);
    await _pump(tester, repo);

    expect(find.text('NurseJobs'), findsOneWidget);
    expect(find.text('NurseNow'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isFalse); // nursejobs, listed first
    expect(switches[1].value, isTrue); // nursenow, listed second
  });

  testWidgets('flipping the switch calls the repository and reloads', (tester) async {
    final repo = _FakeOtpSettingsRepository([_setting(app: 'nursejobs', enabled: false)]);
    await _pump(tester, repo);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repo.updatedApp, 'nursejobs');
    expect(repo.updatedEnabled, isTrue);
    expect(find.text('Last updated by Test Admin'), findsOneWidget);
  });

  testWidgets('reverts the optimistic flip and shows an error when the update fails', (tester) async {
    final repo = _FakeOtpSettingsRepository([_setting(app: 'nursejobs', enabled: false)], throwOnUpdate: true);
    await _pump(tester, repo);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Something went wrong'), findsOneWidget);
  });
}
