import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class ScopeOfWorkRepository {
  final Dio _dio;

  ScopeOfWorkRepository(this._dio);

  /// Public — no auth required, matches GET /scope-of-work server-side.
  Future<ScopeOfWorkModel> get() async {
    final res = await _dio.get(ApiRoutes.scopeOfWork);
    return ScopeOfWorkModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }
}
