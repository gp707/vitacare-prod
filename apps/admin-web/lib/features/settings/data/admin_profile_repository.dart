import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// Self-service password change for the logged-in admin — see
/// AdminService.changeOwnPassword (apps/api). Distinct from AdminUsersRepository,
/// which is super-admin-only management of OTHER admins' accounts.
class AdminProfileRepository {
  final Dio _dio;

  AdminProfileRepository(this._dio);

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.patch('/admin/profile/password', data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
