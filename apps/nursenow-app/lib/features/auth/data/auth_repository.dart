import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';
import 'auth_result.dart';

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  /// [code] is the 4-digit login PIN — an individual logs in with phone +
  /// this code from the very first session onward, same mechanism as a
  /// caregiver. Deliberately minimal compared to caregiver registration —
  /// no gender/age/religion/qualification/documents; those don't apply to
  /// this account type.
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required String code,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.registerIndividual, data: {
        'phone': phone,
        'full_name': fullName,
        'code': code,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Organisation (hospital/rehab/clinic) registration — collects identity/
  /// location fields up front since every requirement it later posts
  /// inherits city/area from here (no per-requirement location).
  Future<AuthResult> registerOrganisation({
    required String phone,
    required String code,
    required String organisationName,
    required String contactPersonName,
    required String organisationType,
    required String city,
    required String area,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.registerOrganisation, data: {
        'phone': phone,
        'code': code,
        'organisation_name': organisationName,
        'contact_person_name': contactPersonName,
        'organisation_type': organisationType,
        'city': city,
        'area': area,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Same endpoint as caregiver login (POST /auth/login/code) — the
  /// backend accepts either role's phone+code and issues the same kind of
  /// non-expiring token either way.
  Future<AuthResult> loginCode(String phone, String code) async {
    try {
      final res = await _dio.post(ApiRoutes.loginCode, data: {'phone': phone, 'code': code});
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
