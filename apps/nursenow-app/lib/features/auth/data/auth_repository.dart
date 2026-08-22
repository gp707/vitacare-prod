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
    required bool termsAccepted,
    required String code,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.registerIndividual, data: {
        'phone': phone,
        'full_name': fullName,
        'terms_accepted': termsAccepted,
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
    required bool termsAccepted,
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
        'terms_accepted': termsAccepted,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Same endpoint as caregiver login (POST /auth/login/code), but phone
  /// is unique per app bucket, not globally — the same phone can also
  /// hold a separate, unlinked NurseJobs caregiver account. `app:
  /// 'nursenow'` tells the backend to look this phone up among
  /// individual/organisation accounts only (whichever this phone actually
  /// registered as — this app doesn't know which ahead of login, that's
  /// decoded from the JWT afterward), never a caregiver account on the
  /// same number.
  Future<AuthResult> loginCode(String phone, String code) async {
    try {
      final res = await _dio.post(
        ApiRoutes.loginCode,
        data: {'phone': phone, 'code': code, 'app': LoginApp.nursenow},
      );
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
