import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class OtpAppSetting {
  final String app;
  final bool enabled;
  final String? updatedByName;
  final String updatedAt;

  const OtpAppSetting({
    required this.app,
    required this.enabled,
    this.updatedByName,
    required this.updatedAt,
  });

  factory OtpAppSetting.fromJson(Map<String, dynamic> json) => OtpAppSetting(
        app: json['app'] as String,
        enabled: json['enabled'] as bool,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class OtpSettingsRepository {
  final Dio _dio;

  OtpSettingsRepository(this._dio);

  Future<List<OtpAppSetting>> list() async {
    try {
      final res = await _dio.get('/admin/otp-settings');
      return (res.data['data'] as List)
          .map((json) => OtpAppSetting.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(String app, bool enabled) async {
    try {
      await _dio.patch('/admin/otp-settings/$app', data: {'enabled': enabled});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
