import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class VerificationStatusResult {
  final String verificationStatus;
  final String? rejectionMessage;
  final String? submittedAt;
  final String? verifiedAt;

  const VerificationStatusResult({
    required this.verificationStatus,
    this.rejectionMessage,
    this.submittedAt,
    this.verifiedAt,
  });

  factory VerificationStatusResult.fromJson(Map<String, dynamic> json) => VerificationStatusResult(
        verificationStatus: json['verification_status'] as String,
        rejectionMessage: json['rejection_message'] as String?,
        submittedAt: json['submitted_at'] as String?,
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

  /// full_name and gender are intentionally not parameters — caregivers
  /// cannot self-edit their own name or gender (admin-only past
  /// registration), so the backend rejects those fields entirely.
  Future<void> updateBasic({
    required int age,
    required List<String> languages,
  }) async {
    try {
      await _dio.put(ApiRoutes.caregiverProfileBasic, data: {
        'age': age,
        'languages': languages,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Identity-sensitive: if the caregiver is currently available/unavailable,
  /// the backend resets them to pending_verification for re-review.
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

  /// Partial self-edit of the advanced-details fields any time after the
  /// initial submission — only non-null fields are sent/written. Requires
  /// advanced_details_completed to already be true (server-enforced).
  /// religion is intentionally not a parameter — once set, it's locked from
  /// self-edit; only admins can change it from that point on.
  Future<void> editAdvancedProfile({
    String? highestQualification,
    List<String>? preferredCities,
  }) async {
    try {
      await _dio.patch(ApiRoutes.caregiverProfileAdvanced, data: {
        if (highestQualification != null) 'highest_qualification': highestQualification,
        if (preferredCities != null) 'preferred_cities': preferredCities,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> submitAdvanced({
    required String highestQualification,
  }) async {
    try {
      final res = await _dio.put(ApiRoutes.caregiverProfileAdvanced, data: {
        'highest_qualification': highestQualification,
        'terms_accepted': true,
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
