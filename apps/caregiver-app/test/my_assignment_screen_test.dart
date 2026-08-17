import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/my_assignment_screen.dart';

JobModel _assignedJob() {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'languages': ['hindi'],
    'salary_monthly': 30000,
    'preferred_gender': 'female',
    'status': 'closed',
    'posted_by': 'admin-1',
    'posted_at': DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'mobility': 'uses_wheelchair',
      'communication': 'verbal',
      'feeding_type': 'oral_needs_assistance',
      'medical_assistance': ['medication_reminders'],
      'has_medical_condition': false,
      'medical_conditions': [],
      'toilet_assistance': ['independent'],
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    },
  });
}

class _FakeJobsRepository extends JobsRepository {
  final JobModel? assignedJob;
  _FakeJobsRepository(this.assignedJob) : super(Dio());

  @override
  Future<JobModel?> getAssignedJob() async => assignedJob;
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows the assigned job details, including care receiver', (tester) async {
    final fakeRepo = _FakeJobsRepository(_assignedJob());
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('78 yrs'), findsOneWidget);
  });

  testWidgets("shows an empty state when there's no assigned job", (tester) async {
    final fakeRepo = _FakeJobsRepository(null);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You don't have an assigned job yet."), findsOneWidget);
  });
}
