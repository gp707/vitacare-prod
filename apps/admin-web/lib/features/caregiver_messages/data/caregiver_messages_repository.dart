import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class CaregiverMessagesRepository {
  final Dio _dio;

  CaregiverMessagesRepository(this._dio);

  Future<List<CaregiverMessageModel>> list() async {
    try {
      final res = await _dio.get(ApiRoutes.adminCaregiverMessages);
      return (res.data['data'] as List)
          .map((json) => CaregiverMessageModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> create(CaregiverMessageModel message) async {
    try {
      await _dio.post(ApiRoutes.adminCaregiverMessages, data: message.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(String id, CaregiverMessageModel message) async {
    try {
      await _dio.patch('${ApiRoutes.adminCaregiverMessages}/$id', data: message.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiRoutes.adminCaregiverMessages}/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
