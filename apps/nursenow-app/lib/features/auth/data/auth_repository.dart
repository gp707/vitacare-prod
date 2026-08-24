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
  ///
  /// [code] and [phoneVerificationToken] are mutually exclusive — exactly
  /// one is required depending on whether OTP mode is enabled for this app
  /// (see otpModeProvider). [phoneVerificationToken] comes from a prior
  /// verifyOtp(purpose: OtpPurpose.register) call.
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required bool termsAccepted,
    String? code,
    String? phoneVerificationToken,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.registerIndividual, data: {
        'phone': phone,
        'full_name': fullName,
        'terms_accepted': termsAccepted,
        if (code != null) 'code': code,
        if (phoneVerificationToken != null) 'phone_verification_token': phoneVerificationToken,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Organisation (hospital/rehab/clinic) registration — collects identity/
  /// location fields up front since every requirement it later posts
  /// inherits city/area from here (no per-requirement location). [code]/
  /// [phoneVerificationToken] are mutually exclusive, same as [register].
  Future<AuthResult> registerOrganisation({
    required String phone,
    required String organisationName,
    required String contactPersonName,
    required String organisationType,
    required String city,
    required String area,
    required bool termsAccepted,
    String? code,
    String? phoneVerificationToken,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.registerOrganisation, data: {
        'phone': phone,
        'organisation_name': organisationName,
        'contact_person_name': contactPersonName,
        'organisation_type': organisationType,
        'city': city,
        'area': area,
        'terms_accepted': termsAccepted,
        if (code != null) 'code': code,
        if (phoneVerificationToken != null) 'phone_verification_token': phoneVerificationToken,
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

  /// Triggers an SMS OTP for [phone]. [purpose] scopes it — a register OTP
  /// can never be replayed to satisfy a login, and vice versa.
  Future<void> sendOtp({required String phone, required String purpose}) async {
    try {
      await _dio.post(ApiRoutes.otpSend, data: {'phone': phone, 'app': LoginApp.nursenow, 'purpose': purpose});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Verifies a previously-sent OTP and returns a short-lived
  /// phone_verification_token proving ownership of [phone] for [purpose] —
  /// fed into [register]/[registerOrganisation] (register purpose) or
  /// [loginOtp] (login purpose) instead of a PIN.
  Future<String> verifyOtp({required String phone, required String otp, required String purpose}) async {
    try {
      final res = await _dio.post(
        ApiRoutes.otpVerify,
        data: {'phone': phone, 'app': LoginApp.nursenow, 'purpose': purpose, 'otp': otp},
      );
      return (res.data['data'] as Map<String, dynamic>)['phone_verification_token'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// OTP counterpart to [loginCode] — proves phone ownership via a
  /// verified token instead of a PIN. Works for an account either with or
  /// without a PIN set, since the token alone is sufficient.
  Future<AuthResult> loginOtp(String phone, String phoneVerificationToken) async {
    try {
      final res = await _dio.post(
        ApiRoutes.loginOtp,
        data: {'phone': phone, 'app': LoginApp.nursenow, 'phone_verification_token': phoneVerificationToken},
      );
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
