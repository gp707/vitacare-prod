import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class ScopeOfWorkWithUpdater {
  final ScopeOfWorkModel scopeOfWork;
  final String? updatedByName;
  final String updatedAt;

  const ScopeOfWorkWithUpdater({
    required this.scopeOfWork,
    this.updatedByName,
    required this.updatedAt,
  });

  factory ScopeOfWorkWithUpdater.fromJson(Map<String, dynamic> json) => ScopeOfWorkWithUpdater(
        scopeOfWork: ScopeOfWorkModel.fromJson(json),
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class ScopeOfWorkRepository {
  final Dio _dio;

  ScopeOfWorkRepository(this._dio);

  Future<ScopeOfWorkWithUpdater> get() async {
    try {
      final res = await _dio.get('/admin/scope-of-work');
      return ScopeOfWorkWithUpdater.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(ScopeOfWorkModel scopeOfWork) async {
    try {
      await _dio.patch('/admin/scope-of-work', data: scopeOfWork.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
