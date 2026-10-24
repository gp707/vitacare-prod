import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// One account row in any Insights report — the same identity shape Error
/// Logs/Tickets resolve (name, phone, `NUR-`/`PAT-`/`ORG-` display id, role).
class InsightAccount {
  final String userId;
  final String fullName;
  final String phone;
  final String role;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final int? caregiverNumber;
  final String? caregiverProfileId;
  final String? verificationStatus;
  final int? patientNumber;
  final int? orgNumber;
  final String? organisationName;

  // Only populated by the "posted but nobody accepted" report.
  final int? postings;
  final int? applicants;
  final int? pendingApplicants;
  final DateTime? firstAppliedAt;

  const InsightAccount({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.createdAt,
    this.lastSeenAt,
    this.caregiverNumber,
    this.caregiverProfileId,
    this.verificationStatus,
    this.patientNumber,
    this.orgNumber,
    this.organisationName,
    this.postings,
    this.applicants,
    this.pendingApplicants,
    this.firstAppliedAt,
  });

  /// e.g. `NUR-500`, `PAT-500` or `ORG-500`, whichever applies.
  String? get displayId =>
      caregiverDisplayId(caregiverNumber) ?? patientDisplayId(patientNumber) ?? organisationDisplayId(orgNumber);

  factory InsightAccount.fromJson(Map<String, dynamic> json) => InsightAccount(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        role: json['role'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastSeenAt: json['last_seen_at'] == null ? null : DateTime.parse(json['last_seen_at'] as String),
        caregiverNumber: json['caregiver_number'] as int?,
        caregiverProfileId: json['caregiver_profile_id'] as String?,
        verificationStatus: json['verification_status'] as String?,
        patientNumber: json['patient_number'] as int?,
        orgNumber: json['org_number'] as int?,
        organisationName: json['organisation_name'] as String?,
        postings: json['postings'] as int?,
        applicants: json['applicants'] as int?,
        pendingApplicants: json['pending_applicants'] as int?,
        firstAppliedAt: json['first_applied_at'] == null ? null : DateTime.parse(json['first_applied_at'] as String),
      );
}

class InsightsPage<T> {
  final List<T> items;
  final PaginationMeta meta;

  const InsightsPage({required this.items, required this.meta});
}

class InsightsSummary {
  final int activeUsers24h;
  final int activeUsers48h;
  final int activeUsers7d;
  final int inactiveSinceRegistration;
  final int postersWithoutAccepted;
  final int caregiversNeverApplied;

  const InsightsSummary({
    required this.activeUsers24h,
    required this.activeUsers48h,
    required this.activeUsers7d,
    required this.inactiveSinceRegistration,
    required this.postersWithoutAccepted,
    required this.caregiversNeverApplied,
  });

  factory InsightsSummary.fromJson(Map<String, dynamic> json) => InsightsSummary(
        activeUsers24h: json['active_users_24h'] as int,
        activeUsers48h: json['active_users_48h'] as int,
        activeUsers7d: json['active_users_7d'] as int,
        inactiveSinceRegistration: json['inactive_since_registration'] as int,
        postersWithoutAccepted: json['posters_without_accepted'] as int,
        caregiversNeverApplied: json['caregivers_never_applied'] as int,
      );
}

/// One row of the "most used buttons/screens" report.
class TopActionRow {
  final String kind;
  final String flow;
  final String screen;
  final String? action;
  final int count;
  final int uniqueUsers;

  const TopActionRow({
    required this.kind,
    required this.flow,
    required this.screen,
    this.action,
    required this.count,
    required this.uniqueUsers,
  });

  factory TopActionRow.fromJson(Map<String, dynamic> json) => TopActionRow(
        kind: json['kind'] as String,
        flow: json['flow'] as String,
        screen: json['screen'] as String,
        action: json['action'] as String?,
        count: json['count'] as int,
        uniqueUsers: json['unique_users'] as int,
      );
}

class AdminInsightsRepository {
  final Dio _dio;

  AdminInsightsRepository(this._dio);

  Future<InsightsSummary> getSummary() async {
    try {
      final res = await _dio.get('/admin/insights/summary');
      return InsightsSummary.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<InsightsPage<InsightAccount>> listActiveUsers({
    required int hours,
    String? role,
    int page = 1,
    int limit = 25,
  }) =>
      _listAccounts('/admin/insights/active-users', {
        'hours': hours,
        if (role != null) 'role': role,
        'page': page,
        'limit': limit,
      });

  Future<InsightsPage<InsightAccount>> listInactiveSinceRegistration({
    required int minAgeHours,
    String? role,
    int page = 1,
    int limit = 25,
  }) =>
      _listAccounts('/admin/insights/inactive-since-registration', {
        'min_age_hours': minAgeHours,
        if (role != null) 'role': role,
        'page': page,
        'limit': limit,
      });

  Future<InsightsPage<InsightAccount>> listPostersWithoutAccepted({int page = 1, int limit = 25}) =>
      _listAccounts('/admin/insights/posters-without-accepted', {'page': page, 'limit': limit});

  Future<InsightsPage<InsightAccount>> listCaregiversNeverApplied({int page = 1, int limit = 25}) =>
      _listAccounts('/admin/insights/caregivers-never-applied', {'page': page, 'limit': limit});

  Future<List<TopActionRow>> getTopActions({
    required String kind,
    required int days,
    String? flow,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get('/admin/insights/top-actions', queryParameters: {
        'kind': kind,
        'days': days,
        if (flow != null) 'flow': flow,
        'limit': limit,
      });
      return (res.data['data'] as List).map((item) => TopActionRow.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<InsightsPage<InsightAccount>> _listAccounts(String path, Map<String, dynamic> query) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      final items =
          (res.data['data'] as List).map((item) => InsightAccount.fromJson(item as Map<String, dynamic>)).toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return InsightsPage(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
