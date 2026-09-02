import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class DutyRequirementsRepository {
  final Dio _dio;

  DutyRequirementsRepository(this._dio);

  /// Public — no auth required, matches GET /duty-requirements server-side.
  Future<DutyRequirementsModel> get() async {
    final res = await _dio.get(ApiRoutes.dutyRequirements);
    return DutyRequirementsModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }
}
