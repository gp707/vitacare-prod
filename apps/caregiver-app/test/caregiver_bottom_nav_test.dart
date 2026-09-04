import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/app/caregiver_bottom_nav.dart';
import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';

JobModel _job({String id = 'job-1', int adminJobNumber = 512, required String status}) {
  return JobModel.fromJson({
    'id': id,
    'admin_job_number': adminJobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': 'closed',
    'posted_by': 'admin-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': {
      'status': status,
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': '2026-08-02T10:00:00Z',
      'rejected_at': null,
      'completed_at': status == 'completed' ? '2026-08-03T10:00:00Z' : null,
      'decided_by_admin': true,
    },
  });
}

OrganisationRequirementModel _requirement({String id = 'req-1', int requirementNumber = 7, required String status}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'frequency_of_care': 'monthly',
    'salary_amount': 40000,
    'accommodation_provided': true,
    'food_provided': false,
    'number_of_vacancies': 1,
    'status': 'closed',
    'posted_at': '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'my_application': {
      'status': status,
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': '2026-08-02T10:00:00Z',
      'rejected_at': null,
      'completed_at': status == 'completed' ? '2026-08-03T10:00:00Z' : null,
      'decided_by_admin': true,
    },
  });
}

class _FakeJobsRepository extends JobsRepository {
  final List<JobModel> assignedJobs;
  final ApiException? error;

  _FakeJobsRepository({this.assignedJobs = const [], this.error}) : super(Dio());

  @override
  Future<List<JobModel>> getAssignedJobs() async {
    if (error != null) throw error!;
    return assignedJobs;
  }
}

class _FakeOrganisationOpeningsRepository extends OrganisationOpeningsRepository {
  final List<OrganisationRequirementModel> assigned;

  _FakeOrganisationOpeningsRepository({this.assigned = const []}) : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> getAssigned() async => assigned;
}

Future<void> _pump(
  WidgetTester tester, {
  _FakeJobsRepository? jobsRepo,
  _FakeOrganisationOpeningsRepository? orgRepo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(jobsRepo ?? _FakeJobsRepository()),
        organisationOpeningsRepositoryProvider.overrideWithValue(orgRepo ?? _FakeOrganisationOpeningsRepository()),
      ],
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: CaregiverBottomNav(currentIndex: 2))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no badge when there are no assigned jobs or requirements', (tester) async {
    await _pump(tester);

    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows a badge with the count of active (not completed) assigned jobs', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository(assignedJobs: [
        _job(id: 'j1', adminJobNumber: 501, status: 'accepted'),
        _job(id: 'j2', adminJobNumber: 502, status: 'accepted'),
      ]),
    );

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('excludes completed jobs from the count', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository(assignedJobs: [
        _job(id: 'j1', adminJobNumber: 501, status: 'accepted'),
        _job(id: 'j2', adminJobNumber: 502, status: 'completed'),
      ]),
    );

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('counts active jobs and active organisation requirements together', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository(assignedJobs: [_job(status: 'accepted')]),
      orgRepo: _FakeOrganisationOpeningsRepository(assigned: [
        _requirement(id: 'r1', requirementNumber: 20, status: 'accepted'),
        _requirement(id: 'r2', requirementNumber: 21, status: 'completed'),
      ]),
    );

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('fails open (no crash, no badge) when the assigned-jobs fetch errors', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository(error: const ApiException(message: 'Network error', code: 'GEN_003')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsNothing);
  });
}
