import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class MaintenanceInfo {
  final String? message;

  const MaintenanceInfo({this.message});
}

class AppMaintenanceRepository {
  final Dio _dio;

  AppMaintenanceRepository(this._dio);

  /// Called once on every cold launch, alongside AppVersionRepository's own
  /// checkForUpdate — this is why it's unauthenticated (GET
  /// /app-maintenance/check takes no token). Returns null when maintenance
  /// is off. Deliberately fails open on any error, same contract as
  /// checkForUpdate above.
  Future<MaintenanceInfo?> checkForMaintenance() async {
    try {
      final res = await _dio.get(ApiRoutes.appMaintenanceCheck, queryParameters: {
        'app': LoginApp.nursenow,
      });
      final data = res.data['data'] as Map<String, dynamic>;
      if (data['enabled'] != true) return null;

      return MaintenanceInfo(message: data['message'] as String?);
    } catch (_) {
      return null;
    }
  }
}
