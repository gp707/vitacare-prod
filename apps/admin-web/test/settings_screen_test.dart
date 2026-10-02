import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/settings/data/job_settings_repository.dart';
import 'package:admin_web/features/settings/data/audit_log_retention_repository.dart';
import 'package:admin_web/features/settings/data/admin_profile_repository.dart';
import 'package:admin_web/features/settings/screens/settings_screen.dart';
import 'package:admin_web/features/rate_card/data/rate_card_repository.dart';
import 'package:admin_web/features/scope_of_work/data/scope_of_work_repository.dart';
import 'package:admin_web/features/duty_requirements/data/duty_requirements_repository.dart';
import 'package:admin_web/features/app_versions/data/app_versions_repository.dart';
import 'package:admin_web/features/app_maintenance/data/app_maintenance_repository.dart';
import 'package:admin_web/features/login_settings/data/otp_settings_repository.dart';

RateCardModel _rateCard({required String frequency, required String title}) {
  return RateCardModel(
    frequencyOfCare: frequency,
    title: title,
    columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
    rowLabels: ['Care'],
    cells: [
      ['26000 pm', '28000 pm', 'Not suggested'],
    ],
  );
}

class _FakeJobSettingsRepository extends JobSettingsRepository {
  JobSettingsWithUpdater current;
  int? savedDays;

  _FakeJobSettingsRepository(this.current) : super(Dio());

  @override
  Future<JobSettingsWithUpdater> get() async => current;

  @override
  Future<void> update(int applyByWindowDays) async {
    savedDays = applyByWindowDays;
    current = JobSettingsWithUpdater(
      applyByWindowDays: applyByWindowDays,
      updatedByName: 'Test Admin',
      updatedAt: '2026-08-30T10:00:00Z',
    );
  }
}

class _FakeAuditLogRetentionRepository extends AuditLogRetentionRepository {
  AuditLogRetentionWithUpdater current;
  int? savedDays;

  _FakeAuditLogRetentionRepository(this.current) : super(Dio());

  @override
  Future<AuditLogRetentionWithUpdater> get() async => current;

  @override
  Future<void> update(int retentionDays) async {
    savedDays = retentionDays;
    current = AuditLogRetentionWithUpdater(
      retentionDays: retentionDays,
      updatedByName: 'Test Admin',
      updatedAt: '2026-08-30T10:00:00Z',
    );
  }
}

class _FakeAdminProfileRepository extends AdminProfileRepository {
  String? capturedCurrent;
  String? capturedNew;
  ApiException? throwOnChange;

  _FakeAdminProfileRepository() : super(Dio());

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    capturedCurrent = currentPassword;
    capturedNew = newPassword;
    if (throwOnChange != null) throw throwOnChange!;
  }
}

class _FakeRateCardRepository extends RateCardRepository {
  Map<String, RateCardModel> current;
  Map<String, String?> updatedByName;
  Map<String, RateCardModel> savedRateCards = {};

  _FakeRateCardRepository(this.current, {Map<String, String?>? updatedByName})
      : updatedByName = updatedByName ?? {},
        super(Dio());

  @override
  Future<List<RateCardWithUpdater>> get() async => [
        for (final frequency in FrequencyOfCare.all)
          RateCardWithUpdater(
            rateCard: current[frequency]!,
            updatedByName: updatedByName[frequency],
            updatedAt: '2026-08-30T10:00:00Z',
          ),
      ];

  @override
  Future<void> update(String frequency, RateCardModel rateCard) async {
    savedRateCards[frequency] = rateCard;
    current[frequency] = rateCard;
    updatedByName[frequency] = 'Test Admin';
  }
}

ScopeOfWorkModel _scopeOfWork() {
  return const ScopeOfWorkModel(
    companionCare: ['Emotional companionship'],
    bedsideCare: ['Diaper changing & hygiene care'],
    criticalCare: ['Catheter care'],
  );
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  ScopeOfWorkModel current;
  String? updatedByName;
  ScopeOfWorkModel? savedScopeOfWork;

  _FakeScopeOfWorkRepository(this.current) : super(Dio());

  @override
  Future<ScopeOfWorkWithUpdater> get() async =>
      ScopeOfWorkWithUpdater(scopeOfWork: current, updatedByName: updatedByName, updatedAt: '2026-08-30T10:00:00Z');

  @override
  Future<void> update(ScopeOfWorkModel scopeOfWork) async {
    savedScopeOfWork = scopeOfWork;
    current = scopeOfWork;
    updatedByName = 'Test Admin';
  }
}

DutyRequirementsModel _dutyRequirements() {
  return const DutyRequirementsModel(
    liveIn: ['Bed, bedsheet, pillow and blanket must be provided.'],
    dayDuty: ['Breakfast and lunch for the nurse.'],
    nightDuty: ['Dinner and breakfast for the nurse.'],
  );
}

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  DutyRequirementsModel current;
  String? updatedByName;
  DutyRequirementsModel? savedDutyRequirements;

  _FakeDutyRequirementsRepository(this.current) : super(Dio());

  @override
  Future<DutyRequirementsWithUpdater> get() async => DutyRequirementsWithUpdater(
      dutyRequirements: current, updatedByName: updatedByName, updatedAt: '2026-08-30T10:00:00Z');

  @override
  Future<void> update(DutyRequirementsModel dutyRequirements) async {
    savedDutyRequirements = dutyRequirements;
    current = dutyRequirements;
    updatedByName = 'Test Admin';
  }
}

AppMinVersion _version({String platform = 'android', String minVersion = '1.0.0'}) {
  return AppMinVersion.fromJson({
    'platform': platform,
    'min_version': minVersion,
    'store_url': null,
    'update_message': null,
    'updated_by_name': null,
    'updated_at': '2026-08-17T10:00:00Z',
  });
}

class _FakeAppVersionsRepository extends AppVersionsRepository {
  List<AppMinVersion> versions;

  _FakeAppVersionsRepository(this.versions) : super(Dio());

  @override
  Future<List<AppMinVersion>> list() async => versions;

  @override
  Future<void> update(String platform,
      {required String minVersion, String? storeUrl, String? updateMessage}) async {
    versions = versions
        .map((v) => v.platform == platform ? _version(platform: platform, minVersion: minVersion) : v)
        .toList();
  }
}

AppMaintenance _maintenance({bool enabled = false, String? message}) {
  return AppMaintenance.fromJson({
    'enabled': enabled,
    'message': message,
    'updated_by_name': null,
    'updated_at': '2026-08-17T10:00:00Z',
  });
}

class _FakeAppMaintenanceRepository extends AppMaintenanceRepository {
  AppMaintenance row;

  _FakeAppMaintenanceRepository(this.row) : super(Dio());

  @override
  Future<AppMaintenance> get() async => row;

  @override
  Future<void> update({required bool enabled, String? message}) async {
    row = _maintenance(enabled: enabled, message: message);
  }
}

OtpAppSetting _setting({String app = 'nursejobs', bool enabled = false}) {
  return OtpAppSetting.fromJson({
    'app': app,
    'enabled': enabled,
    'updated_by_name': null,
    'updated_at': '2026-08-24T10:00:00Z',
  });
}

class _FakeOtpSettingsRepository extends OtpSettingsRepository {
  List<OtpAppSetting> settings;
  String? updatedApp;
  bool? updatedEnabled;

  _FakeOtpSettingsRepository(this.settings) : super(Dio());

  @override
  Future<List<OtpAppSetting>> list() async => settings;

  @override
  Future<void> update(String app, bool enabled) async {
    updatedApp = app;
    updatedEnabled = enabled;
    settings = settings.map((s) => s.app == app ? _setting(app: app, enabled: enabled) : s).toList();
  }
}

class _Repos {
  final _FakeJobSettingsRepository jobSettings;
  final _FakeAuditLogRetentionRepository auditLogRetention;
  final _FakeAdminProfileRepository adminProfile;
  final _FakeRateCardRepository rateCard;
  final _FakeScopeOfWorkRepository scopeOfWork;
  final _FakeDutyRequirementsRepository dutyRequirements;
  final _FakeAppVersionsRepository appVersions;
  final _FakeAppMaintenanceRepository appMaintenance;
  final _FakeOtpSettingsRepository otpSettings;

  _Repos({
    _FakeJobSettingsRepository? jobSettings,
    _FakeAuditLogRetentionRepository? auditLogRetention,
    _FakeAdminProfileRepository? adminProfile,
    _FakeRateCardRepository? rateCard,
    _FakeScopeOfWorkRepository? scopeOfWork,
    _FakeDutyRequirementsRepository? dutyRequirements,
    _FakeAppVersionsRepository? appVersions,
    _FakeAppMaintenanceRepository? appMaintenance,
    _FakeOtpSettingsRepository? otpSettings,
  })  : jobSettings = jobSettings ??
            _FakeJobSettingsRepository(const JobSettingsWithUpdater(applyByWindowDays: 3)),
        auditLogRetention = auditLogRetention ??
            _FakeAuditLogRetentionRepository(const AuditLogRetentionWithUpdater(retentionDays: 180)),
        adminProfile = adminProfile ?? _FakeAdminProfileRepository(),
        rateCard = rateCard ??
            _FakeRateCardRepository({
              FrequencyOfCare.daily: _rateCard(frequency: FrequencyOfCare.daily, title: 'Daily Guidelines'),
              FrequencyOfCare.monthly: _rateCard(frequency: FrequencyOfCare.monthly, title: 'Monthly Guidelines'),
            }),
        scopeOfWork = scopeOfWork ?? _FakeScopeOfWorkRepository(_scopeOfWork()),
        dutyRequirements = dutyRequirements ?? _FakeDutyRequirementsRepository(_dutyRequirements()),
        appVersions = appVersions ??
            _FakeAppVersionsRepository([_version(platform: 'android', minVersion: '1.2.0')]),
        appMaintenance = appMaintenance ?? _FakeAppMaintenanceRepository(_maintenance()),
        otpSettings = otpSettings ?? _FakeOtpSettingsRepository([_setting(app: 'nursejobs')]);
}

Future<void> _pump(WidgetTester tester, _Repos repos) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        jobSettingsRepositoryProvider.overrideWithValue(repos.jobSettings),
        auditLogRetentionRepositoryProvider.overrideWithValue(repos.auditLogRetention),
        adminProfileRepositoryProvider.overrideWithValue(repos.adminProfile),
        rateCardRepositoryProvider.overrideWithValue(repos.rateCard),
        scopeOfWorkRepositoryProvider.overrideWithValue(repos.scopeOfWork),
        dutyRequirementsRepositoryProvider.overrideWithValue(repos.dutyRequirements),
        appVersionsRepositoryProvider.overrideWithValue(repos.appVersions),
        appMaintenanceRepositoryProvider.overrideWithValue(repos.appMaintenance),
        otpSettingsRepositoryProvider.overrideWithValue(repos.otpSettings),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  // The tab strip is scrollable (isScrollable: true) and now has 7 tabs —
  // Login Settings can sit off the 1400px test surface, so scroll it into
  // view before tapping rather than relying on it already being visible.
  final finder = find.widgetWithText(Tab, label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows all 7 tabs and defaults to General', (tester) async {
    await _pump(tester, _Repos());

    for (final label in [
      'General',
      'Rate Card',
      'Scope of Work',
      'Duty Requirements',
      'App Versions',
      'Maintenance Mode',
      'Login Settings',
    ]) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    // General tab content is visible without switching tabs. "Change
    // Password" matches both the section title and the submit button, so
    // just assert the section title is present.
    expect(find.text('Apply-By Window'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Change Password'), findsOneWidget);
  });

  group('General tab', () {
    testWidgets('loads and saves the apply-by window', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      final field = find.widgetWithText(TextField, '3');
      expect(field, findsOneWidget);

      await tester.enterText(field, '5');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(repos.jobSettings.savedDays, 5);
      expect(find.text('Apply-by window saved'), findsOneWidget);
      expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
    });

    testWidgets('rejects a non-positive apply-by window without calling the repository', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      await tester.enterText(find.widgetWithText(TextField, '3'), '0');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(repos.jobSettings.savedDays, isNull);
      expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
    });

    testWidgets('loads and saves the audit log retention window', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      final field = find.widgetWithText(TextField, '180');
      expect(field, findsOneWidget);

      await tester.enterText(field, '90');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').at(1));
      await tester.pumpAndSettle();

      expect(repos.auditLogRetention.savedDays, 90);
      expect(find.text('Audit log retention saved'), findsOneWidget);
      expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
    });

    testWidgets('rejects a non-positive audit log retention window without calling the repository', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      await tester.enterText(find.widgetWithText(TextField, '180'), '0');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').at(1));
      await tester.pumpAndSettle();

      expect(repos.auditLogRetention.savedDays, isNull);
      expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
    });

    testWidgets('changes the password when current + confirmation are valid', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      await tester.enterText(find.widgetWithText(TextField, 'Current Password'), 'oldpass');
      await tester.enterText(find.widgetWithText(TextField, 'New Password'), 'newpass1');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm New Password'), 'newpass1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(repos.adminProfile.capturedCurrent, 'oldpass');
      expect(repos.adminProfile.capturedNew, 'newpass1');
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('blocks submission when new password and confirmation do not match', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);

      await tester.enterText(find.widgetWithText(TextField, 'Current Password'), 'oldpass');
      await tester.enterText(find.widgetWithText(TextField, 'New Password'), 'newpass1');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm New Password'), 'different');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(repos.adminProfile.capturedCurrent, isNull);
      expect(find.text('New password and confirmation do not match'), findsOneWidget);
    });

    testWidgets('surfaces a server error, e.g. wrong current password', (tester) async {
      final adminProfile = _FakeAdminProfileRepository()
        ..throwOnChange = ApiException(message: 'Current password is incorrect', code: 'AUTH_015');
      final repos = _Repos(adminProfile: adminProfile);
      await _pump(tester, repos);

      await tester.enterText(find.widgetWithText(TextField, 'Current Password'), 'wrongpass');
      await tester.enterText(find.widgetWithText(TextField, 'New Password'), 'newpass1');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm New Password'), 'newpass1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(find.text('Current password is incorrect'), findsOneWidget);
    });
  });

  group('Rate Card tab', () {
    testWidgets('loads both frequencies and saves an edit', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);
      await _selectTab(tester, 'Rate Card');

      expect(find.widgetWithText(TextField, 'Daily Guidelines'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Monthly Guidelines'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Daily Guidelines'), 'Updated Daily');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(repos.rateCard.savedRateCards[FrequencyOfCare.daily]!.title, 'Updated Daily');
      expect(find.text('Daily rate card saved'), findsOneWidget);
    });
  });

  group('Scope of Work tab', () {
    testWidgets('loads all 3 tiers and saves an edit', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);
      await _selectTab(tester, 'Scope of Work');

      expect(find.text('Companion Care'), findsOneWidget);
      expect(find.text('Bedside Care'), findsOneWidget);
      expect(find.text('Critical Care'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Emotional companionship'),
        'Emotional & social companionship',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repos.scopeOfWork.savedScopeOfWork!.companionCare, contains('Emotional & social companionship'));
      expect(find.text('Scope of work saved'), findsOneWidget);
    });
  });

  group('Duty Requirements tab', () {
    testWidgets('loads all 3 shifts and saves an edit', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);
      await _selectTab(tester, 'Duty Requirements');

      expect(find.text('24Hrs - Live In'), findsOneWidget);
      expect(find.text('12Hrs Day Shift (8am to 8pm)'), findsOneWidget);
      expect(find.text('12Hrs Night Shift (8pm to 8am)'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Breakfast and lunch for the nurse.'),
        'Breakfast, lunch and snacks for the nurse.',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repos.dutyRequirements.savedDutyRequirements!.dayDuty,
          contains('Breakfast, lunch and snacks for the nurse.'));
      expect(find.text('Duty requirements saved'), findsOneWidget);
    });
  });

  group('App Versions tab', () {
    testWidgets('lists one row per platform and saves an edit', (tester) async {
      final repos = _Repos(
        appVersions: _FakeAppVersionsRepository([
          _version(platform: 'android', minVersion: '1.2.0'),
          _version(platform: 'ios', minVersion: '2.0.0'),
        ]),
      );
      await _pump(tester, repos);
      await _selectTab(tester, 'App Versions');

      expect(find.text('Minimum version: 1.2.0'), findsOneWidget);
      expect(find.text('Minimum version: 2.0.0'), findsOneWidget);

      // Edit the first row (android) and confirm only that row changes —
      // ios's own 2.0.0 row is untouched.
      await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Minimum version (e.g. 1.2.0)'), '1.3.0');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Minimum version: 1.3.0'), findsOneWidget);
      expect(find.text('Minimum version: 2.0.0'), findsOneWidget);
    });
  });

  group('Maintenance Mode tab', () {
    testWidgets('enables maintenance and saves the message', (tester) async {
      final repos = _Repos();
      await _pump(tester, repos);
      await _selectTab(tester, 'Maintenance Mode');

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Message shown to users').first,
        'App is in maintenance mode, it will be available after 10am IST.',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(repos.appMaintenance.row.enabled, isTrue);
      expect(
        repos.appMaintenance.row.message,
        'App is in maintenance mode, it will be available after 10am IST.',
      );
      expect(find.text('Maintenance settings saved'), findsOneWidget);
    });
  });

  group('Login Settings tab', () {
    testWidgets('lists both apps and flips a toggle', (tester) async {
      final repos = _Repos(
        otpSettings: _FakeOtpSettingsRepository([
          _setting(app: 'nursejobs', enabled: false),
          _setting(app: 'nursenow', enabled: false),
        ]),
      );
      await _pump(tester, repos);
      await _selectTab(tester, 'Login Settings');

      expect(find.text('NurseJobs'), findsOneWidget);
      expect(find.text('NurseNow'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(repos.otpSettings.updatedApp, 'nursejobs');
      expect(repos.otpSettings.updatedEnabled, isTrue);
    });
  });
}
