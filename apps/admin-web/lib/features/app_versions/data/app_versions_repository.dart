import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// An account (caregiver / patient / organisation) named in an audience, or found by the picker.
class AudienceAccount {
  final String userId;
  final String fullName;
  final String phone;
  /// caregiver | individual | organisation
  final String role;
  final int? caregiverNumber;
  final int? patientNumber;
  final int? orgNumber;
  /// hospital | rehab | clinic | agency — organisations only.
  final String? organisationType;
  final String? organisationName;

  const AudienceAccount({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    this.caregiverNumber,
    this.patientNumber,
    this.orgNumber,
    this.organisationType,
    this.organisationName,
  });

  /// NUR-/PAT-/ORG- id, when the account has one.
  String? get displayLabel => switch (role) {
        'caregiver' => caregiverDisplayId(caregiverNumber),
        'individual' => patientDisplayId(patientNumber),
        'organisation' => organisationDisplayId(orgNumber),
        _ => null,
      };

  /// "Caregiver", "Patient / Family", or the organisation type ("Hospital", "Agency"…).
  String get kindLabel => switch (role) {
        'caregiver' => 'Caregiver',
        'individual' => 'Patient / Family',
        'organisation' => OrganisationType.displayNames[organisationType] ?? 'Organisation',
        _ => role,
      };

  /// What to call the account in a list: an organisation by its name, anyone else by their name.
  String get title => role == 'organisation' && (organisationName?.isNotEmpty ?? false) ? organisationName! : fullName;

  /// "NUR-574 · vita health dummy" — the compact form for chips and result rows.
  String get chipLabel => [if (displayLabel != null) displayLabel!, title].join(' · ');

  factory AudienceAccount.fromJson(Map<String, dynamic> json) => AudienceAccount(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        role: json['role'] as String,
        caregiverNumber: (json['caregiver_number'] as num?)?.toInt(),
        patientNumber: (json['patient_number'] as num?)?.toInt(),
        orgNumber: (json['org_number'] as num?)?.toInt(),
        organisationType: json['organisation_type'] as String?,
        organisationName: json['organisation_name'] as String?,
      );
}

/// Who a minimum version applies to — what an edit sends.
class AppVersionAudience {
  /// [AppVersionAudienceMode.all] or [AppVersionAudienceMode.selected].
  final String mode;
  final List<String> categories;
  final List<String> userIds;

  const AppVersionAudience({required this.mode, this.categories = const [], this.userIds = const []});

  const AppVersionAudience.everyone() : this(mode: AppVersionAudienceMode.all);
}

class AppMinVersion {
  final String platform;
  final String minVersion;
  final String? storeUrl;
  final String? updateMessage;
  final String? updatedByName;
  final String updatedAt;
  /// [AppVersionAudienceMode.all] unless admin narrowed it.
  final String audienceMode;
  final List<String> audienceCategories;
  final List<AudienceAccount> audienceUsers;

  const AppMinVersion({
    required this.platform,
    required this.minVersion,
    this.storeUrl,
    this.updateMessage,
    this.updatedByName,
    required this.updatedAt,
    this.audienceMode = AppVersionAudienceMode.all,
    this.audienceCategories = const [],
    this.audienceUsers = const [],
  });

  bool get appliesToEveryone => audienceMode != AppVersionAudienceMode.selected;

  /// One line saying who it applies to: "Everyone", or "Caregivers, Hospitals + 2 specific accounts".
  String get audienceSummary {
    if (appliesToEveryone) return 'Everyone';
    final parts = <String>[
      for (final c in AppVersionAudienceCategory.all)
        if (audienceCategories.contains(c)) AppVersionAudienceCategory.displayNames[c]!,
    ];
    final n = audienceUsers.length;
    final accounts = n == 0 ? null : '$n specific account${n == 1 ? '' : 's'}';
    if (parts.isEmpty && accounts == null) return 'Nobody (nothing selected)';
    if (accounts == null) return parts.join(', ');
    if (parts.isEmpty) return accounts;
    return '${parts.join(', ')} + $accounts';
  }

  factory AppMinVersion.fromJson(Map<String, dynamic> json) => AppMinVersion(
        platform: json['platform'] as String,
        minVersion: json['min_version'] as String,
        storeUrl: json['store_url'] as String?,
        updateMessage: json['update_message'] as String?,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
        audienceMode: (json['audience_mode'] as String?) ?? AppVersionAudienceMode.all,
        audienceCategories: List<String>.from(json['audience_categories'] as List? ?? const []),
        audienceUsers: ((json['audience_users'] as List?) ?? const [])
            .map((a) => AudienceAccount.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

class AppVersionsRepository {
  final Dio _dio;

  AppVersionsRepository(this._dio);

  /// Returns both platform rows (android + ios) for the single JustHeal
  /// binary — each is independently editable/saveable. Used to carry a
  /// per-app (NurseJobs/NurseNow) dimension too (migration 068), back when
  /// they shipped as two independent binaries; collapsed by migration 074
  /// once they merged into one (see CLAUDE.md's "Merged into one binary
  /// with NurseJobs").
  Future<List<AppMinVersion>> list() async {
    try {
      final res = await _dio.get('/admin/app-versions');
      return (res.data['data'] as List)
          .map((json) => AppMinVersion.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [audience] null leaves who it applies to exactly as it is.
  Future<void> update(
    String platform, {
    required String minVersion,
    String? storeUrl,
    String? updateMessage,
    AppVersionAudience? audience,
  }) async {
    try {
      await _dio.patch('/admin/app-versions/$platform', data: {
        'min_version': minVersion,
        if (storeUrl != null && storeUrl.isNotEmpty) 'store_url': storeUrl,
        if (updateMessage != null && updateMessage.isNotEmpty)
          'update_message': updateMessage,
        if (audience != null) ...{
          'audience_mode': audience.mode,
          'audience_categories': audience.categories,
          'audience_user_ids': audience.userIds,
        },
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Caregiver / patient / organisation accounts matching [query] (name, phone, NUR-/PAT-/ORG- id,
  /// organisation name), optionally within one audience category. Needs 2+ characters.
  Future<List<AudienceAccount>> searchAccounts(String query, {String? category}) async {
    try {
      final res = await _dio.get('/admin/accounts/search', queryParameters: {
        'q': query,
        if (category != null) 'category': category,
      });
      return (res.data['data'] as List).map((a) => AudienceAccount.fromJson(a as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
