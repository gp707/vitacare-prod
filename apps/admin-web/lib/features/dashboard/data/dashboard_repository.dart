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
