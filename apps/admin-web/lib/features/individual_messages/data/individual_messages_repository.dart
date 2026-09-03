import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class IndividualMessagesRepository {
  final Dio _dio;

  IndividualMessagesRepository(this._dio);

  Future<List<IndividualMessageModel>> list() async {
    try {
      final res = await _dio.get(ApiRoutes.adminIndividualMessages);
      return (res.data['data'] as List)
          .map((json) => IndividualMessageModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> create(IndividualMessageModel message) async {
    try {
      await _dio.post(ApiRoutes.adminIndividualMessages, data: message.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(String id, IndividualMessageModel message) async {
    try {
      await _dio.patch('${ApiRoutes.adminIndividualMessages}/$id', data: message.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiRoutes.adminIndividualMessages}/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
