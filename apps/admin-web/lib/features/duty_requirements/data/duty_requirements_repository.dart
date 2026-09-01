import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class DutyRequirementsWithUpdater {
  final DutyRequirementsModel dutyRequirements;
  final String? updatedByName;
  final String updatedAt;

  const DutyRequirementsWithUpdater({
    required this.dutyRequirements,
    this.updatedByName,
    required this.updatedAt,
  });

  factory DutyRequirementsWithUpdater.fromJson(Map<String, dynamic> json) => DutyRequirementsWithUpdater(
        dutyRequirements: DutyRequirementsModel.fromJson(json),
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class DutyRequirementsRepository {
  final Dio _dio;

  DutyRequirementsRepository(this._dio);

  Future<DutyRequirementsWithUpdater> get() async {
    try {
      final res = await _dio.get('/admin/duty-requirements');
      return DutyRequirementsWithUpdater.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(DutyRequirementsModel dutyRequirements) async {
    try {
      await _dio.patch('/admin/duty-requirements', data: dutyRequirements.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
