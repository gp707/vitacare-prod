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
  Future<AuthResult> register({
    required String phone,
    required String fullName,
    required String gender,
    required int age,
    required List<String> languages,
    required String code,
    required String religion,
    required String highestQualification,
    required bool termsAccepted,
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
        'highest_qualification': highestQualification,
        'terms_accepted': termsAccepted,
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
}
