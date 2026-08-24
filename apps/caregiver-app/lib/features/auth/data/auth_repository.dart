import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';
import 'auth_result.dart';

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  /// [code] is the 4-digit login PIN, set here at registration — caregivers
  /// log in with phone + this code from the very first session onward.
  /// [religion] and [highestQualification] are set once here — religion is
  /// locked from self-edit afterward (admin-only past this point);
  /// highestQualification remains self-editable later via
  /// ProfileRepository.editProfile. [preferredCities] also remains
  /// self-editable later. There is no separate "Advanced Details" step
  /// anymore — everything is collected in this one registration.
  ///
  /// [code] and [phoneVerificationToken] are mutually exclusive — exactly
  /// one is required depending on whether OTP mode is enabled for this app
  /// (see otpModeProvider). [phoneVerificationToken] comes from a prior
  /// verifyOtp(purpose: OtpPurpose.register) call. The backend is the
  /// actual source of truth for which one is required; the caller just
  /// passes whichever one this session's flow produced.
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required String gender,
    required int age,
    required List<String> languages,
    required String religion,
    required String highestQualification,
    required bool termsAccepted,
    String? code,
    String? phoneVerificationToken,
    List<String>? preferredCities,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.register, data: {
        'phone': phone,
        'full_name': fullName,
        'gender': gender,
        'age': age,
        'languages': languages,
        'religion': religion,
        'highest_qualification': highestQualification,
        'terms_accepted': termsAccepted,
        if (code != null) 'code': code,
        if (phoneVerificationToken != null) 'phone_verification_token': phoneVerificationToken,
        if (preferredCities != null) 'preferred_cities': preferredCities,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Phone is unique per app bucket, not globally — the same phone can
  /// also hold a separate, unlinked NurseNow account. `app: 'nursejobs'`
  /// tells the backend to look this phone up among caregiver accounts
  /// only, never a NurseNow individual/organisation account on the same
  /// number.
  Future<AuthResult> loginCode(String phone, String code) async {
    try {
      final res = await _dio.post(
        ApiRoutes.loginCode,
        data: {'phone': phone, 'code': code, 'app': LoginApp.nursejobs},
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
      await _dio.post(ApiRoutes.otpSend, data: {'phone': phone, 'app': LoginApp.nursejobs, 'purpose': purpose});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Verifies a previously-sent OTP and returns a short-lived
  /// phone_verification_token proving ownership of [phone] for [purpose] —
  /// fed into [register] (register purpose) or [loginOtp] (login purpose)
  /// instead of a PIN.
  Future<String> verifyOtp({required String phone, required String otp, required String purpose}) async {
    try {
      final res = await _dio.post(
        ApiRoutes.otpVerify,
        data: {'phone': phone, 'app': LoginApp.nursejobs, 'purpose': purpose, 'otp': otp},
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
        data: {'phone': phone, 'app': LoginApp.nursejobs, 'phone_verification_token': phoneVerificationToken},
      );
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
