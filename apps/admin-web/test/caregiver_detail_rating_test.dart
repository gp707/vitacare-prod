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
  double? overallRating,
}) {
  return AdminCaregiverDetail(
    engagements: engagements,
    overallRating: overallRating,
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
  testWidgets('a rated caregiver shows the stars in an arc over her picture and her overall rating', (tester) async {
    await _pump(tester, _FakeAdminCaregiversRepository(_detail(overallRating: 4.5)));
    expect(find.byKey(const Key('caregiver-rating-arc')), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_half), findsOneWidget);
    expect(find.text('Overall rating: 4.5 / 5'), findsOneWidget);
  });

  testWidgets('at the cap she shows five full stars (an average that is already 5 stays 5)', (tester) async {
    await _pump(tester, _FakeAdminCaregiversRepository(_detail(overallRating: 5)));
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    expect(find.text('Overall rating: 5.0 / 5'), findsOneWidget);
  });

  testWidgets('an unrated caregiver has no arc and no rating line', (tester) async {
    await _pump(tester, _FakeAdminCaregiversRepository(_detail()));
    expect(find.byKey(const Key('caregiver-rating-arc')), findsNothing);
    expect(find.byKey(const Key('caregiver-overall-rating-text')), findsNothing);
  });
}
