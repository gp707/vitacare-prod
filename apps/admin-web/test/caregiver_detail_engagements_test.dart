import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_detail_screen.dart';

AdminCaregiverDetail _detail({
  String status = 'assigned',
  List<CaregiverEngagement> engagements = const [],
}) {
  return AdminCaregiverDetail(
    engagements: engagements,
    userId: 'user-1',
    profileId: 'profile-1',
    caregiverNumber: 500,
    fullName: 'Test Caregiver',
    phone: '+919876543210',
    gender: 'female',
    age: 28,
    languages: const ['hindi'],
    preferredCities: const [],
    otherDocumentUrls: const [],
    termsAccepted: false,
    verificationStatus: status,
    hasPendingEdits: false,
    adminNotes: const AdminNotes(),
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminCaregiversRepository extends AdminCaregiversRepository {
  AdminCaregiverDetail detail;
  String? capturedStatus;
  String? capturedRejectionMessage;
  String? resetCodeProfileId;
  String? resetCodeValue;
  String? editedProfileId;
  Map<String, dynamic>? editedFields;

  _FakeAdminCaregiversRepository(this.detail) : super(Dio());

  @override
  Future<void> editProfile(String profileId, Map<String, dynamic> fields) async {
    editedProfileId = profileId;
    editedFields = fields;
  }

  @override
  Future<AdminCaregiverDetail> getDetail(String profileId) async => detail;

  @override
  Future<String> updateStatus(String profileId, String status,
      {String? rejectionMessage}) async {
    capturedStatus = status;
    capturedRejectionMessage = rejectionMessage;
    return status;
  }

  @override
  Future<void> resetCode(String profileId, String code) async {
    resetCodeProfileId = profileId;
    resetCodeValue = code;
  }
}

class _FakeAuditLogsRepository extends AuditLogsRepository {
  _FakeAuditLogsRepository() : super(Dio());

  @override
  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    return const AuditLogListResult(
      items: [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, totalPages: 1),
    );
  }
}

Future<void> _pump(
    WidgetTester tester, _FakeAdminCaregiversRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(
                userId: 'admin-1', role: 'super_admin'),
        ),
        adminCaregiversRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider
            .overrideWithValue(_FakeAuditLogsRepository()),
      ],
      child: const MaterialApp(
          home: CaregiverDetailScreen(profileId: 'profile-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows who accepted the caregiver, with start date and status', (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(engagements: const [
      CaregiverEngagement(
        isRequirement: false,
        status: 'accepted',
        patientJobNumber: 539,
        posterName: 'Hansa',
        posterPhone: '+919686895746',
        posterRole: 'individual',
        posterNumber: 625,
        city: 'bangalore',
        area: 'Whitefield',
        dutyType: 'day_duty',
        startDate: '2027-01-24',
        acceptedAt: '2026-11-07T12:13:55Z',
        acceptedByName: 'Hansa',
      ),
      CaregiverEngagement(
        isRequirement: true,
        status: 'completed',
        requirementNumber: 512,
        posterName: 'City Hospital',
        posterRole: 'organisation',
        posterNumber: 510,
        acceptedAt: '2026-10-01T09:00:00Z',
        completedAt: '2026-10-20T09:00:00Z',
      ),
    ]));
    await _pump(tester, repo);

    expect(find.text('Currently accepted by (1)'), findsOneWidget);
    expect(find.text('PAT-JOB-539'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Start date: 2027-01-24'), findsOneWidget);
    expect(find.text('Accepted by: PAT-625 · Hansa'), findsOneWidget);
    expect(find.text('Phone: +919686895746'), findsOneWidget);
    // History: a completed organisation requirement has no start date.
    expect(find.text('ORG-JOB-512'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Start date: Not set (organisation requirement)'), findsOneWidget);
  });

  testWidgets('shows no accepted-work section when there are no engagements', (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail());
    await _pump(tester, repo);

    expect(find.textContaining('Currently accepted by'), findsNothing);
    expect(find.textContaining('Accepted work'), findsNothing);
  });
}
