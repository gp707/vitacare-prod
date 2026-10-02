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
  /// checkForUpdate above. This is the single real check for the whole
  /// JustHeal binary — it used to pass an `app` bucket so NurseJobs and
  /// NurseNow could be taken down independently (migration 068); collapsed
  /// to a single global singleton by migration 074 once they merged into
  /// one binary.
  Future<MaintenanceInfo?> checkForMaintenance() async {
    try {
      final res = await _dio.get(ApiRoutes.appMaintenanceCheck);
      final data = res.data['data'] as Map<String, dynamic>;
      if (data['enabled'] != true) return null;

      return MaintenanceInfo(message: data['message'] as String?);
    } catch (_) {
      return null;
    }
  }
}
