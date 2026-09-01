import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/messages_screen.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

JobModel _requirement({
  String status = 'active',
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'patient_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (careReceiver != null) 'care_receiver': careReceiver,
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  final List<JobModel> requirements;
  final ApiException? error;

  _FakeIndividualRepository({this.requirements = const [], this.error}) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async {
    if (error != null) throw error!;
    return requirements;
  }
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => const ScopeOfWorkModel(
        companionCare: ['Companion bullet'],
        bedsideCare: ['Bedside bullet'],
        criticalCare: ['Critical bullet'],
      );
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = const SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: false,
            ),
        ),
      ],
      child: const MaterialApp(home: MessagesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a friendly empty state when there is nothing to say', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: []));

    expect(find.text('No messages right now.'), findsOneWidget);
  });

  testWidgets('shows the automatic messages for a live requirement', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'active')]),
    );

    expect(find.textContaining('You can edit this job and change salary'), findsOneWidget);
    expect(find.textContaining('You can post one requirement at a time'), findsOneWidget);
    expect(find.textContaining('consider widening your scope'), findsOneWidget);
  });

  testWidgets('shows nothing for a closed requirement', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'closed')]),
    );

    expect(find.text('No messages right now.'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(error: ApiException(message: 'Network error', code: 'GEN_003')),
    );

    expect(find.text('Network error'), findsOneWidget);
  });
}
