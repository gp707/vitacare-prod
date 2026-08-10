import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/network/api_client.dart';
import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/data/auth_repository.dart';
import 'package:admin_web/features/dashboard/data/dashboard_repository.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/admin_management/data/admin_users_repository.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';

/// Exercises the exact repository code the screens call, against a real
/// locally-running instance of apps/api (http://localhost:3000/v1) and the
/// real Supabase project. Deliberately kept out of test/ so plain
/// `flutter test` / `melos run test` stay hermetic (no server dependency).
///
/// To run:
///   1. Start the API server: cd apps/api && node dist/main.js &
///   2. Seed a super_admin test user (password hashed with bcrypt, 4 rounds
///      is fine for a throwaway):
///        node -e "console.log(require('bcrypt').hashSync('AdminPass123', 4))"
///        psql "$DATABASE_URL" -c "INSERT INTO users (email, phone, password_hash, full_name, role, is_active) VALUES ('admin-web-super-e2e@e2e-test.local', '+917000040999', '(hash from step above)', 'Admin Web Super', 'super_admin', true);"
///   3. cd apps/admin-web && flutter test test_integration/admin_flow_integration_test.dart
///   4. Clean up (audit_logs first — it references users without ON DELETE CASCADE):
///        DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700004%')
///          OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700004%');
///        DELETE FROM users WHERE phone LIKE '+91700004%' AND role = 'caregiver';
///        DELETE FROM users WHERE phone LIKE '+91700004%' OR email LIKE '%@e2e-test.local';
/// Uses the +91700004xxxx test phone range, distinct from every apps/api
/// e2e suite (+91700000/1/2/3xxxx).
void main() {
  late LocalStorage localStorage;
  late AuthRepository authRepo;
  late DashboardRepository dashboardRepo;
  late AdminCaregiversRepository caregiversRepo;
  late AdminUsersRepository usersRepo;
  late AuditLogsRepository auditLogsRepo;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    localStorage = await LocalStorage.create();
    final apiClient = ApiClient(localStorage);
    authRepo = AuthRepository(apiClient.dio);
    dashboardRepo = DashboardRepository(apiClient.dio);
    caregiversRepo = AdminCaregiversRepository(apiClient.dio);
    usersRepo = AdminUsersRepository(apiClient.dio);
    auditLogsRepo = AuditLogsRepository(apiClient.dio);
  });

  String testPhone(String suffix) => '+91700004$suffix';

  Future<void> loginAsSuperAdmin() async {
    final result = await authRepo.loginEmail('admin-web-super-e2e@e2e-test.local', 'AdminPass123');
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
  }

  test('logs in as super admin and reads dashboard stats', () async {
    await loginAsSuperAdmin();
    final stats = await dashboardRepo.getStats();
    expect(stats.totalCaregivers, greaterThanOrEqualTo(0));
  });

  test('rejects the wrong password with ApiException(AUTH_003)', () async {
    await expectLater(
      authRepo.loginEmail('admin-web-super-e2e@e2e-test.local', 'wrong-password'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_003')),
    );
  });

  test('lists a freshly-registered caregiver and walks call-verify + status flow', () async {
    await loginAsSuperAdmin();

    // Register directly via the auth endpoint's raw path (AuthRepository in
    // this app is admin-only — loginEmail — there's no caregiver-facing UI
    // here) so there's a real row for the admin to act on.
    final apiClient = ApiClient(localStorage);
    final registerRes = await apiClient.dio.post('/auth/register', data: {
      'phone': testPhone('0001'),
      'full_name': 'Integration Subject',
      'gender': 'male',
      'age': 29,
      'languages': ['hindi'],
      'code': '1234',
    });
    final profileId = registerRes.data['data']['profile_id'] as String;
    final targetUserId = registerRes.data['data']['user_id'] as String;

    final list = await caregiversRepo.list(
      const CaregiverListFilters(search: 'Integration Subject'),
    );
    expect(list.items, hasLength(1));
    expect(list.items.first.profileId, profileId);

    final detail = await caregiversRepo.getDetail(profileId);
    expect(detail.verificationStatus, 'pending_call');

    final afterCallVerify = await caregiversRepo.markCallVerified(profileId);
    expect(afterCallVerify, 'call_verified');

    await expectLater(
      caregiversRepo.updateStatus(profileId, 'available'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ADMIN_001')),
    );

    await caregiversRepo.upsertNotes(profileId, internalNotes: 'Looks solid', rate24hrsLiveIn: 25000);
    final detailWithNotes = await caregiversRepo.getDetail(profileId);
    expect(detailWithNotes.adminNotes.internalNotes, 'Looks solid');
    expect(detailWithNotes.adminNotes.rate24hrsLiveIn, 25000);

    final auditResult = await auditLogsRepo.list(
      AuditLogListFilters(targetUserId: targetUserId, action: 'call_verified'),
    );
    expect(auditResult.items, hasLength(1));
    expect(auditResult.items.first.beforeValue, {'verification_status': 'pending_call'});
    expect(auditResult.items.first.afterValue, {'verification_status': 'call_verified'});
  });

  test('admin can edit profile fields, assign work types/service modes, and set salary', () async {
    await loginAsSuperAdmin();

    final apiClient = ApiClient(localStorage);
    final registerRes = await apiClient.dio.post('/auth/register', data: {
      'phone': testPhone('0003'),
      'full_name': 'Edit Integration Subject',
      'gender': 'male',
      'age': 28,
      'languages': ['hindi'],
      'code': '1234',
    });
    final profileId = registerRes.data['data']['profile_id'] as String;

    await caregiversRepo.editProfile(profileId, {
      'full_name': 'Edited By Admin',
      'age': 31,
      'current_address': '456 Admin St',
    });
    final editedDetail = await caregiversRepo.getDetail(profileId);
    expect(editedDetail.fullName, 'Edited By Admin');
    expect(editedDetail.age, 31);
    expect(editedDetail.currentAddress, '456 Admin St');
    expect(editedDetail.verificationStatus, 'pending_call');

    final workTypes = await caregiversRepo.assignWorkTypes(profileId, ['companion_care', 'bedside_care']);
    expect(workTypes, ['companion_care', 'bedside_care']);

    final serviceModes = await caregiversRepo.assignServiceModes(profileId, ['24hrs_live_in']);
    expect(serviceModes, ['24hrs_live_in']);

    final salary = await caregiversRepo.updateSalary(profileId, 26000);
    expect(salary, 26000);

    final finalDetail = await caregiversRepo.getDetail(profileId);
    expect(finalDetail.workTypes.toSet(), {'companion_care', 'bedside_care'});
    expect(finalDetail.serviceModes, ['24hrs_live_in']);
    expect(finalDetail.salary, 26000);
  });

  test('admin can upload/replace a caregiver selfie and documents', () async {
    await loginAsSuperAdmin();

    final apiClient = ApiClient(localStorage);
    final registerRes = await apiClient.dio.post('/auth/register', data: {
      'phone': testPhone('0004'),
      'full_name': 'Doc Upload Integration Subject',
      'gender': 'female',
      'age': 27,
      'languages': ['hindi'],
      'code': '1234',
    });
    final profileId = registerRes.data['data']['profile_id'] as String;

    final selfieBytes = Uint8List.fromList('admin uploaded selfie'.codeUnits);
    final selfiePath = await caregiversRepo.uploadSelfie(profileId, selfieBytes, 'selfie.jpg');
    expect(selfiePath, 'caregiver-documents/$profileId/selfie.jpg');

    final qualBytes = Uint8List.fromList('admin uploaded qualification'.codeUnits);
    final qualPath =
        await caregiversRepo.uploadDocument(profileId, qualBytes, 'qual.pdf', 'qualification');
    expect(qualPath, 'caregiver-documents/$profileId/qualification.pdf');

    final detail = await caregiversRepo.getDetail(profileId);
    expect(detail.selfiePhotoUrl, isNotNull);
    expect(detail.qualificationDocumentUrl, isNotNull);
  });

  test('creates, lists, and deactivates a regular admin', () async {
    await loginAsSuperAdmin();
    const email = 'created-via-integration-test@e2e-test.local';

    await usersRepo.create(
      email: email,
      phone: testPhone('0002'),
      fullName: 'Integration Created Admin',
      password: 'AdminPass123',
    );

    final admins = await usersRepo.list();
    final created = admins.firstWhere((a) => a.email == email);
    expect(created.role, 'admin');
    expect(created.isActive, isTrue);

    await usersRepo.deactivate(created.userId);

    await expectLater(
      authRepo.loginEmail(email, 'AdminPass123'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_004')),
    );
  });
}
