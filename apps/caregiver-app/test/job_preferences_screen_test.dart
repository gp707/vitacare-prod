import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/profile/data/profile_repository.dart';
import 'package:caregiver_app/features/jobs/screens/job_preferences_screen.dart';

CaregiverProfileModel _profile({
  List<String> preferredCities = const [],
  List<String> preferredDutyTypes = const [],
  int? minSalaryPerDay,
  int? minSalaryPerMonth,
}) {
  return CaregiverProfileModel.fromJson({
    'user_id': 'u1',
    'profile_id': 'p1',
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'gender': 'male',
    'age': 30,
    'languages': ['hindi'],
    'other_document_urls': [],
    'terms_accepted': true,
    'verification_status': 'available',
    'created_at': '2026-08-01T10:00:00Z',
    'highest_qualification': 'rn_above_2_years',
    'religion': 'hindu',
    'preferred_cities': preferredCities,
    'preferred_duty_types': preferredDutyTypes,
    'min_salary_per_day': minSalaryPerDay,
    'min_salary_per_month': minSalaryPerMonth,
  });
}

class _FakeProfileRepository extends ProfileRepository {
  final CaregiverProfileModel profile;
  bool editProfileCalled = false;

  _FakeProfileRepository(this.profile) : super(Dio());

  @override
  Future<CaregiverProfileModel> getProfile() async => profile;

  @override
  Future<String> editProfile({
    int? age,
    List<String>? languages,
    String? highestQualification,
    List<String>? preferredCities,
    List<String>? preferredDutyTypes,
    int? minSalaryPerDay,
    int? minSalaryPerMonth,
  }) async {
    editProfileCalled = true;
    return 'available';
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

/// JobPreferencesScreen is temporarily read-only (2026-08-23): Preferred
/// Shift/Duty Type and both minimum-salary fields always display "select
/// everything" (all 3 shifts, ₹0) regardless of what's actually stored,
/// there's no Save button, and nothing can be edited. Preferred City is
/// still shown as the caregiver's real stored value, just non-interactive.
void main() {
  testWidgets('shows all 3 shifts checked and both minimums as 0, regardless of what is actually stored',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(
      preferredDutyTypes: [DutyType.dayDuty],
      minSalaryPerDay: 1500,
      minSalaryPerMonth: 30000,
    ));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final type in DutyType.all) {
      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, DutyType.displayNames[type]!),
      );
      expect(chip.selected, isTrue, reason: '$type should show as selected');
      expect(chip.onSelected, isNull, reason: '$type should not be tappable');
    }
    expect(find.text('Minimum Salary — ₹/day'), findsOneWidget);
    expect(find.text('Minimum Salary — ₹/month'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    // The real stored values (1500/30000/day_duty-only) are never shown.
    expect(find.text('1500'), findsNothing);
    expect(find.text('30000'), findsNothing);
  });

  testWidgets('shows the real stored preferred cities, but not interactively', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(preferredCities: ['bangalore']));
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final bangaloreChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Bangalore'));
    expect(bangaloreChip.selected, isTrue);
    expect(bangaloreChip.onSelected, isNull);
    final mumbaiChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Mumbai'));
    expect(mumbaiChip.selected, isFalse);
    expect(mumbaiChip.onSelected, isNull);
  });

  testWidgets('has no Save button and never calls editProfile — editing is temporarily unavailable',
      (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);
    expect(fakeRepo.editProfileCalled, isFalse);
  });
}
