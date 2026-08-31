import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class VerificationStatusResult {
  final String verificationStatus;
  final String? rejectionMessage;
  final String? verifiedAt;

  const VerificationStatusResult({
    required this.verificationStatus,
    this.rejectionMessage,
    this.verifiedAt,
  });

  factory VerificationStatusResult.fromJson(Map<String, dynamic> json) => VerificationStatusResult(
        verificationStatus: json['verification_status'] as String,
        rejectionMessage: json['rejection_message'] as String?,
        verifiedAt: json['verified_at'] as String?,
      );
}

class ProfileRepository {
  final Dio _dio;

  ProfileRepository(this._dio);

  Future<CaregiverProfileModel> getProfile() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverProfile);
      return CaregiverProfileModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Identity-sensitive: if the caregiver is currently available/unavailable
  /// or rejected, the backend resets them to pending_call for re-review.
  Future<String> updatePhone(String phone) async {
    try {
      final res = await _dio.patch(ApiRoutes.caregiverProfilePhone, data: {'phone': phone});
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PIN change never triggers re-review, unlike phone/Aadhaar.
  Future<void> updateCode(String code) async {
    try {
      await _dio.patch(ApiRoutes.caregiverProfileCode, data: {'code': code});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Single self-edit endpoint for every caregiver-editable field — only
  /// non-null fields are sent/written. full_name, gender, and religion are
  /// intentionally not parameters — locked from self-edit once set at
  /// registration; only admins can change them. While rejected, any actual
  /// change here auto-resubmits (sends the caregiver back to pending_call)
  /// server-side — no separate "resubmit" call needed.
  Future<String> editProfile({
    int? age,
    List<String>? languages,
    String? highestQualification,
  }) async {
    try {
      final res = await _dio.patch(ApiRoutes.caregiverProfile, data: {
        if (age != null) 'age': age,
        if (languages != null) 'languages': languages,
        if (highestQualification != null) 'highest_qualification': highestQualification,
      });
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Uses MultipartFile.fromBytes (not .fromFile) — this app runs on Flutter
  /// Web (no filesystem path to give dio there) as well as mobile, so bytes
  /// are the only representation that works on every platform.
  Future<void> uploadSelfie(Uint8List bytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      await _dio.post(ApiRoutes.caregiverProfileSelfie, data: formData);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> uploadDocument(Uint8List bytes, String filename, String documentType) async {
    try {
      final formData = FormData.fromMap({
        'document_type': documentType,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      await _dio.post(ApiRoutes.caregiverProfileDocuments, data: formData);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<VerificationStatusResult> getVerificationStatus() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverVerificationStatus);
      return VerificationStatusResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// SPEC.md 6.4: call after registration, on each app launch, and whenever
  /// the FCM token refreshes.
  Future<void> updateFcmToken(String token) async {
    try {
      await _dio.put(ApiRoutes.caregiverFcmToken, data: {'token': token});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
