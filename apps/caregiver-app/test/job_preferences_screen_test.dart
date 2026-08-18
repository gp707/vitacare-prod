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
  Map<String, dynamic> captured = {};

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
    captured = {
      'preferredCities': preferredCities,
      'preferredDutyTypes': preferredDutyTypes,
      'minSalaryPerDay': minSalaryPerDay,
      'minSalaryPerMonth': minSalaryPerMonth,
    };
    return 'available';
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('loads and shows the current preferences', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile(
      preferredCities: ['bangalore'],
      preferredDutyTypes: [DutyType.dayDuty],
      minSalaryPerDay: 1500,
    ));
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
    final dayDutyChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, DutyType.displayNames[DutyType.dayDuty]!),
    );
    expect(dayDutyChip.selected, isTrue);
    expect(find.text('1500'), findsOneWidget);
  });

  testWidgets('Save sends only what actually changed and pops with true', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    late bool? popResult;
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              child: const Text('open'),
              onPressed: () async {
                popResult = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const JobPreferencesScreen()),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Mumbai'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Minimum Salary — ₹/day (optional)'), '2000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.editProfileCalled, isTrue);
    expect(fakeRepo.captured['preferredCities'], ['mumbai']);
    expect(fakeRepo.captured['minSalaryPerDay'], 2000);
    expect(fakeRepo.captured['minSalaryPerMonth'], isNull);
    expect(fakeRepo.captured['preferredDutyTypes'], isNull);
    expect(popResult, isTrue);
  });

  testWidgets('rejects a non-numeric minimum salary without calling the repository', (tester) async {
    final fakeRepo = _FakeProfileRepository(_profile());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Minimum Salary — ₹/month (optional)'), 'abc');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fakeRepo.editProfileCalled, isFalse);
    expect(find.text('Minimum salary per month must be a positive number'), findsOneWidget);
  });
}
