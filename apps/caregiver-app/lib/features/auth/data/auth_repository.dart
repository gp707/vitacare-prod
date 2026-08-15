import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';
import 'auth_result.dart';

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  /// [code] is the 4-digit login PIN, set here at registration — caregivers
  /// log in with phone + this code from the very first session onward.
  /// [religion] is set once here and locked from self-edit afterward — only
  /// admins can change it from that point on. [preferredCities] remains
  /// self-editable later via ProfileRepository.editAdvancedProfile.
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required String gender,
    required int age,
    required List<String> languages,
    required String code,
    required String religion,
    List<String>? preferredCities,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.register, data: {
        'phone': phone,
        'full_name': fullName,
        'gender': gender,
        'age': age,
        'languages': languages,
        'code': code,
        'religion': religion,
        if (preferredCities != null) 'preferred_cities': preferredCities,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AuthResult> loginCode(String phone, String code) async {
    try {
      final res = await _dio.post(ApiRoutes.loginCode, data: {'phone': phone, 'code': code});
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
