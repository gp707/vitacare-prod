import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/audit_logs/data/audit_logs_repository.dart';
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_detail_screen.dart';

AdminCaregiverDetail _detail({
  String? selfiePhotoUrl,
  String? qualificationDocumentUrl,
  String? aadhaarDocumentUrl,
  List<String> otherDocumentUrls = const [],
}) {
  return AdminCaregiverDetail(
    userId: 'user-1',
    profileId: 'profile-1',
    caregiverNumber: 500,
    fullName: 'Test Caregiver',
    phone: '+919876543210',
    gender: 'female',
    age: 28,
    selfiePhotoUrl: selfiePhotoUrl,
    languages: const ['hindi'],
    preferredCities: const [],
    qualificationDocumentUrl: qualificationDocumentUrl,
    aadhaarDocumentUrl: aadhaarDocumentUrl,
    otherDocumentUrls: otherDocumentUrls,
    termsAccepted: false,
    verificationStatus: 'available',
    hasPendingEdits: false,
    adminNotes: const AdminNotes(),
    createdAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminCaregiversRepository extends AdminCaregiversRepository {
  final AdminCaregiverDetail detail;
  List<CaregiverDocumentVersion> history;
  Object? historyError;
  Object? deleteError;
  String? deletedVersionId;

  _FakeAdminCaregiversRepository(this.detail, {this.history = const []}) : super(Dio());

  @override
  Future<AdminCaregiverDetail> getDetail(String profileId) async => detail;

  @override
  Future<List<CaregiverDocumentVersion>> getDocumentHistory(String profileId) async {
    if (historyError != null) throw historyError!;
    return history;
  }

  @override
  Future<void> deleteDocumentVersion(String profileId, String versionId) async {
    if (deleteError != null) throw deleteError!;
    deletedVersionId = versionId;
    history = history.where((v) => v.id != versionId).toList();
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

Future<void> _pump(WidgetTester tester, _FakeAdminCaregiversRepository repo,
    {String role = 'super_admin'}) async {
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
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: role),
        ),
        adminCaregiversRepositoryProvider.overrideWithValue(repo),
        auditLogsRepositoryProvider.overrideWithValue(_FakeAuditLogsRepository()),
      ],
      child: const MaterialApp(home: CaregiverDetailScreen(profileId: 'profile-1')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDocumentsTab(WidgetTester tester) async {
  await tester.tap(find.text('Documents'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no "History" button for a document that has never been uploaded', (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail());
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    expect(find.text('Not uploaded'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'History'), findsNothing);
  });

  testWidgets('shows a "History" button next to an uploaded selfie', (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(selfiePhotoUrl: 'https://signed/selfie'));
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    expect(find.widgetWithText(TextButton, 'History'), findsOneWidget);
  });

  testWidgets('tapping "History" opens a dialog listing every version, newest first, with uploader and a '
      'View link', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie-new'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-2',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-new',
          uploadedByName: 'Admin One',
          uploadedByRole: 'admin',
          createdAt: '2026-08-02T10:00:00Z',
        ),
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-old',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();

    expect(find.text('Selfie — Version History'), findsOneWidget);
    expect(find.text('Uploaded by admin — Admin One'), findsOneWidget);
    expect(find.text('Uploaded by caregiver'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'View'), findsNWidgets(2));
  });

  testWidgets('filters the history dialog to just this document type — an aadhaar version never leaks '
      'into the selfie dialog', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(
        selfiePhotoUrl: 'https://signed/selfie',
        aadhaarDocumentUrl: 'https://signed/aadhaar',
      ),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-selfie',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
        CaregiverDocumentVersion(
          id: 'doc-aadhaar',
          documentType: 'aadhaar',
          signedUrl: 'https://signed/aadhaar',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);
  });

  testWidgets('distinguishes between two "other document" slots by their own slot index', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(otherDocumentUrls: const ['https://signed/other-1', 'https://signed/other-2']),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-other-1',
          documentType: 'other',
          slotIndex: 1,
          signedUrl: 'https://signed/other-1',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
        CaregiverDocumentVersion(
          id: 'doc-other-2',
          documentType: 'other',
          slotIndex: 2,
          signedUrl: 'https://signed/other-2',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History').first);
    await tester.pumpAndSettle();

    expect(find.text('Other Document 1 — Version History'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);
  });

  testWidgets('shows a friendly error, not a crash, when the history fetch fails', (tester) async {
    final repo = _FakeAdminCaregiversRepository(_detail(selfiePhotoUrl: 'https://signed/selfie'));
    repo.historyError = Exception('boom');
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();

    expect(find.text('Selfie — Version History'), findsOneWidget);
    expect(find.text('Failed to load history'), findsOneWidget);
  });

  testWidgets('a super_admin sees a Delete action per version', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie-new'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-old',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo, role: 'super_admin');
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('a regular admin (not super_admin) sees no Delete action', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie-new'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-old',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo, role: 'admin');
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
      'tapping Delete asks for confirmation; confirming calls deleteDocumentVersion and removes it from the list',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie-new'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-2',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-new',
          uploadedByRole: 'admin',
          uploadedByName: 'Admin One',
          createdAt: '2026-08-02T10:00:00Z',
        ),
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie-old',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();

    expect(find.text('Delete this version?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedVersionId, 'doc-1');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('cancelling the confirmation dialog does not call deleteDocumentVersion', (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deletedVersionId, isNull);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('shows a snackbar with the server message when deletion is refused (e.g. the current version)',
      (tester) async {
    final repo = _FakeAdminCaregiversRepository(
      _detail(selfiePhotoUrl: 'https://signed/selfie'),
      history: [
        CaregiverDocumentVersion(
          id: 'doc-1',
          documentType: 'selfie',
          signedUrl: 'https://signed/selfie',
          uploadedByRole: 'caregiver',
          createdAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    repo.deleteError = const ApiException(
        code: 'UPLOAD_007', message: 'Cannot delete the current version of a document');
    await _pump(tester, repo);
    await _openDocumentsTab(tester);

    await tester.tap(find.widgetWithText(TextButton, 'History'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot delete the current version of a document'), findsOneWidget);
  });
}
