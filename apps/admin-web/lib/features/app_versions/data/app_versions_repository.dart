import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class AppMinVersion {
  final String platform;
  final String minVersion;
  final String? storeUrl;
  final String? updateMessage;
  final String? updatedByName;
  final String updatedAt;

  const AppMinVersion({
    required this.platform,
    required this.minVersion,
    this.storeUrl,
    this.updateMessage,
    this.updatedByName,
    required this.updatedAt,
  });

  factory AppMinVersion.fromJson(Map<String, dynamic> json) => AppMinVersion(
        platform: json['platform'] as String,
        minVersion: json['min_version'] as String,
        storeUrl: json['store_url'] as String?,
        updateMessage: json['update_message'] as String?,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class AppVersionsRepository {
  final Dio _dio;

  AppVersionsRepository(this._dio);

  Future<List<AppMinVersion>> list() async {
    try {
      final res = await _dio.get('/admin/app-versions');
      return (res.data['data'] as List)
          .map((json) => AppMinVersion.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(
    String platform, {
    required String minVersion,
    String? storeUrl,
    String? updateMessage,
  }) async {
    try {
      await _dio.patch('/admin/app-versions/$platform', data: {
        'min_version': minVersion,
        if (storeUrl != null && storeUrl.isNotEmpty) 'store_url': storeUrl,
        if (updateMessage != null && updateMessage.isNotEmpty) 'update_message': updateMessage,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
