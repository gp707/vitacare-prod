import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class AdminUser {
  final String userId;
  final String email;
  final String phone;
  final String fullName;
  final String role;
  final bool isActive;
  final String createdAt;

  const AdminUser({
    required this.userId,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        userId: json['user_id'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        isActive: json['is_active'] as bool,
        createdAt: json['created_at'] as String,
      );
}

class AdminUsersRepository {
  final Dio _dio;

  AdminUsersRepository(this._dio);

  Future<List<AdminUser>> list() async {
    try {
      final res = await _dio.get('/admin/users');
      return (res.data['data'] as List)
          .map((json) => AdminUser.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> create({
    required String email,
    required String phone,
    required String fullName,
    required String password,
  }) async {
    try {
      await _dio.post('/admin/users', data: {
        'email': email,
        'phone': phone,
        'full_name': fullName,
        'password': password,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deactivate(String userId) async {
    try {
      await _dio.delete('/admin/users/$userId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> activate(String userId) async {
    try {
      await _dio.patch('/admin/users/$userId/activate');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> updateRole(String userId, String role) async {
    try {
      await _dio.patch('/admin/users/$userId/role', data: {'role': role});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
