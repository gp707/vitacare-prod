import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class DashboardStats {
  final int totalCaregivers;
  final int pendingCall;
  final int available;
  final int unavailable;
  final int assigned;
  final int rejected;
  final int pendingEditsCount;
  final int newRegistrations24h;
  final int newRegistrations7d;
  // jobs.status = 'pending_review' + organisation_requirements.status =
  // 'pending_review' combined — every NurseNow posting currently awaiting
  // admin's legitimacy review, across both posting types.
  final int jobsPendingApproval;
  final int newOrganisations7d;
  final int newIndividuals7d;

  const DashboardStats({
    required this.totalCaregivers,
    required this.pendingCall,
    required this.available,
    required this.unavailable,
    required this.assigned,
    required this.rejected,
    required this.pendingEditsCount,
    required this.newRegistrations24h,
    required this.newRegistrations7d,
    required this.jobsPendingApproval,
    required this.newOrganisations7d,
    required this.newIndividuals7d,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        totalCaregivers: json['total_caregivers'] as int,
        pendingCall: json['pending_call'] as int,
        available: json['available'] as int,
        unavailable: json['unavailable'] as int,
        assigned: json['assigned'] as int,
        rejected: json['rejected'] as int,
        pendingEditsCount: json['pending_edits_count'] as int,
        newRegistrations24h: json['new_registrations_24h'] as int,
        newRegistrations7d: json['new_registrations_7d'] as int,
        jobsPendingApproval: json['jobs_pending_approval'] as int,
        newOrganisations7d: json['new_organisations_7d'] as int,
        newIndividuals7d: json['new_individuals_7d'] as int,
      );
}

class DashboardRepository {
  final Dio _dio;

  DashboardRepository(this._dio);

  Future<DashboardStats> getStats() async {
    try {
      final res = await _dio.get('/admin/dashboard/stats');
      return DashboardStats.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
