import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/features/app_versions/data/app_versions_repository.dart';
import 'package:admin_web/features/settings/widgets/app_versions_settings_section.dart';

AudienceAccount _caregiver() => const AudienceAccount(
      userId: 'cg-1',
      fullName: 'vita health dummy',
      phone: '+918792902302',
      role: 'caregiver',
      caregiverNumber: 574,
    );

AudienceAccount _patient() => const AudienceAccount(
      userId: 'pt-1',
      fullName: 'Hansa',
      phone: '+919845204336',
      role: 'individual',
      patientNumber: 625,
    );

AudienceAccount _agency() => const AudienceAccount(
      userId: 'org-1',
      fullName: 'Veer',
      phone: '+918197397993',
      role: 'organisation',
      orgNumber: 609,
      organisationType: 'agency',
      organisationName: 'Vita Health',
    );

AppMinVersion _row({
  String platform = 'android',
  String mode = 'all',
  List<String> categories = const [],
  List<AudienceAccount> users = const [],
}) =>
    AppMinVersion(
      platform: platform,
      minVersion: '1.2.0',
      storeUrl: 'https://play.google.com/x',
      updatedAt: '2026-11-21T10:00:00Z',
      audienceMode: mode,
      audienceCategories: categories,
      audienceUsers: users,
    );

class _FakeRepo extends AppVersionsRepository {
  List<AppMinVersion> rows;
  List<AudienceAccount> searchable;
  // what the last save sent
  String? savedPlatform;
  AppVersionAudience? savedAudience;
  int saveCalls = 0;
  String? lastQuery;

  _FakeRepo(this.rows, {this.searchable = const []}) : super(Dio());

  @override
  Future<List<AppMinVersion>> list() async => rows;

  @override
  Future<void> update(String platform,
      {required String minVersion, String? storeUrl, String? updateMessage, AppVersionAudience? audience}) async {
    saveCalls++;
    savedPlatform = platform;
    savedAudience = audience;
  }

  @override
  Future<List<AudienceAccount>> searchAccounts(String query, {String? category}) async {
    lastQuery = query;
    return searchable.where((a) => a.chipLabel.toLowerCase().contains(query.toLowerCase())).toList();
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [appVersionsRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: Scaffold(body: AppVersionsSettingsSection())),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openEdit(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.text('Edit').at(index));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
  await tester.pumpAndSettle();
  // the "Force update?" confirmation
  await tester.tap(find.text('Save').last);
  await tester.pumpAndSettle();
}

void main() {
  group('the card says who a minimum applies to', () {
    testWidgets('Everyone by default', (tester) async {
      await _pump(tester, _FakeRepo([_row(), _row(platform: 'ios')]));
      expect(find.byKey(const Key('audience-summary-android')), findsOneWidget);
      expect(find.text('Applies to: Everyone'), findsNWidgets(2));
    });

    testWidgets('a selected audience lists the categories and the accounts', (tester) async {
      await _pump(
        tester,
        _FakeRepo([_row(mode: 'selected', categories: ['hospital', 'caregiver'], users: [_patient(), _agency()]), _row(platform: 'ios')]),
      );
      // categories in a fixed, readable order, then the accounts
      expect(find.text('Applies to: Caregivers, Hospitals + 2 specific accounts'), findsOneWidget);
      expect(find.textContaining('PAT-625 · Hansa'), findsOneWidget);
      expect(find.textContaining('ORG-609 · Vita Health'), findsOneWidget);
    });

    testWidgets('one account reads as singular, and only accounts reads without categories', (tester) async {
      await _pump(tester, _FakeRepo([_row(mode: 'selected', users: [_patient()]), _row(platform: 'ios')]));
      expect(find.text('Applies to: 1 specific account'), findsOneWidget);
    });
  });

  group('choosing who in the edit dialog', () {
    testWidgets('opens on Everyone and shows no category or account controls', (tester) async {
      await _pump(tester, _FakeRepo([_row()]));
      await _openEdit(tester);
      expect(find.byKey(const Key('audience-mode')), findsOneWidget);
      expect(find.byKey(const Key('audience-category-caregiver')), findsNothing);
      expect(find.byKey(const Key('audience-add-account')), findsNothing);
    });

    testWidgets('Selected only shows all six categories', (tester) async {
      await _pump(tester, _FakeRepo([_row()]));
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      for (final c in ['individual', 'caregiver', 'hospital', 'rehab', 'clinic', 'agency']) {
        expect(find.byKey(Key('audience-category-$c')), findsOneWidget, reason: c);
      }
      expect(find.text('Patients / Families'), findsOneWidget);
      expect(find.text('Agencies'), findsOneWidget);
      expect(find.byKey(const Key('audience-add-account')), findsOneWidget);
    });

    testWidgets('saving Everyone sends mode "all"', (tester) async {
      final repo = _FakeRepo([_row()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await _save(tester);
      expect(repo.savedAudience!.mode, AppVersionAudienceMode.all);
      expect(repo.savedAudience!.categories, isEmpty);
      expect(repo.savedAudience!.userIds, isEmpty);
    });

    testWidgets('saving selected categories sends them in a fixed order', (tester) async {
      final repo = _FakeRepo([_row()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      // tapped out of order on purpose
      await tester.tap(find.byKey(const Key('audience-category-agency')));
      await tester.tap(find.byKey(const Key('audience-category-caregiver')));
      await tester.tap(find.byKey(const Key('audience-category-hospital')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repo.savedPlatform, 'android');
      expect(repo.savedAudience!.mode, AppVersionAudienceMode.selected);
      expect(repo.savedAudience!.categories, ['caregiver', 'hospital', 'agency']);
      expect(repo.savedAudience!.userIds, isEmpty);
    });

    testWidgets('a category can be unticked again', (tester) async {
      final repo = _FakeRepo([_row(mode: 'selected', categories: ['caregiver', 'rehab'])]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.byKey(const Key('audience-category-rehab')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repo.savedAudience!.categories, ['caregiver']);
    });

    testWidgets('an existing selected audience opens pre-filled (categories and accounts)', (tester) async {
      await _pump(tester, _FakeRepo([_row(mode: 'selected', categories: ['hospital'], users: [_patient()])]));
      await _openEdit(tester);
      expect(tester.widget<FilterChip>(find.byKey(const Key('audience-category-hospital'))).selected, isTrue);
      expect(tester.widget<FilterChip>(find.byKey(const Key('audience-category-caregiver'))).selected, isFalse);
      expect(find.byKey(const Key('audience-account-pt-1')), findsOneWidget);
      expect(find.textContaining('PAT-625 · Hansa (Patient / Family)'), findsOneWidget);
    });

    testWidgets('Selected only with nothing picked is refused with a hint, and nothing is sent', (tester) async {
      final repo = _FakeRepo([_row()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audience-empty-hint')), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Pick at least one category or account, or choose Everyone.'), findsWidgets);
      expect(repo.saveCalls, 0);
    });

    testWidgets('the confirmation names who will be forced to update', (tester) async {
      final repo = _FakeRepo([_row()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('audience-category-caregiver')));
      await tester.tap(find.byKey(const Key('audience-category-agency')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anyone in Caregivers, Agencies on an older android version'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(repo.saveCalls, 0);
    });
  });

  group('picking specific accounts', () {
    testWidgets('search finds accounts of every kind; choosing one adds it as a chip, and it is saved by id', (tester) async {
      final repo = _FakeRepo([_row()], searchable: [_caregiver(), _patient(), _agency()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('audience-add-account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-picker-empty')), findsOneWidget); // asks for 2+ characters

      await tester.enterText(find.byKey(const Key('account-picker-search')), 'han');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.lastQuery, 'han');
      expect(find.byKey(const Key('account-result-pt-1')), findsOneWidget);
      expect(find.textContaining('Patient / Family · +919845204336'), findsOneWidget);

      await tester.tap(find.byKey(const Key('account-result-pt-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audience-account-pt-1')), findsOneWidget);

      await _save(tester);
      expect(repo.savedAudience!.mode, AppVersionAudienceMode.selected);
      expect(repo.savedAudience!.userIds, ['pt-1']);
      expect(repo.savedAudience!.categories, isEmpty);
    });

    testWidgets('an organisation shows its name and type, a caregiver its NUR id', (tester) async {
      final repo = _FakeRepo([_row()], searchable: [_caregiver(), _agency()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('audience-add-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('account-picker-search')), 'vita');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('ORG-609 · Vita Health'), findsOneWidget);
      expect(find.textContaining('Agency · +918197397993'), findsOneWidget);
      expect(find.text('NUR-574 · vita health dummy'), findsOneWidget);
    });

    testWidgets('an account already chosen is shown as added and cannot be added twice', (tester) async {
      final repo = _FakeRepo([_row(mode: 'selected', users: [_patient()])], searchable: [_patient()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.byKey(const Key('audience-add-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('account-picker-search')), 'han');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const Key('account-result-pt-1'))).enabled, isFalse);
    });

    testWidgets('a chip\'s x removes the account', (tester) async {
      final repo = _FakeRepo([_row(mode: 'selected', categories: ['rehab'], users: [_patient(), _caregiver()])]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.descendant(of: find.byKey(const Key('audience-account-pt-1')), matching: find.byTooltip('Delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audience-account-pt-1')), findsNothing);
      await _save(tester);
      expect(repo.savedAudience!.userIds, ['cg-1']);
    });

    testWidgets('one character is not searched', (tester) async {
      final repo = _FakeRepo([_row()], searchable: [_patient()]);
      await _pump(tester, repo);
      await _openEdit(tester);
      await tester.tap(find.text('Selected only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('audience-add-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('account-picker-search')), 'h');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.lastQuery, isNull);
      expect(find.byKey(const Key('account-picker-empty')), findsOneWidget);
    });
  });

  group('the model', () {
    test('an older server that sends no audience means everyone', () {
      final v = AppMinVersion.fromJson({
        'platform': 'android',
        'min_version': '1.0.2',
        'updated_at': '2026-11-14T20:07:00Z',
      });
      expect(v.appliesToEveryone, isTrue);
      expect(v.audienceSummary, 'Everyone');
    });

    test('reads the audience and its accounts', () {
      final v = AppMinVersion.fromJson({
        'platform': 'android',
        'min_version': '1.0.2',
        'updated_at': '2026-11-14T20:07:00Z',
        'audience_mode': 'selected',
        'audience_categories': ['rehab', 'individual'],
        'audience_users': [
          {'user_id': 'cg-1', 'full_name': 'X', 'phone': '+91', 'role': 'caregiver', 'caregiver_number': 574},
        ],
      });
      expect(v.appliesToEveryone, isFalse);
      expect(v.audienceSummary, 'Patients / Families, Rehabs + 1 specific account');
      expect(v.audienceUsers.single.displayLabel, 'NUR-574');
    });

    test('a selected audience with nothing in it says so', () {
      final v = AppMinVersion.fromJson({
        'platform': 'ios',
        'min_version': '1.0.0',
        'updated_at': 'x',
        'audience_mode': 'selected',
      });
      expect(v.audienceSummary, 'Nobody (nothing selected)');
    });
  });
}
