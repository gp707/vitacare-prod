import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import 'admin_caregiver_models.dart';

class CaregiverListFilters {
  final String? search;
  final String? status;
  final String? qualification;
  final String? gender;
  final List<String>? languages;
  final String? city;
  final String? fromDate;
  final String? toDate;
  final String sort;
  final String order;
  final int page;
  final int limit;

  const CaregiverListFilters({
    this.search,
    this.status,
    this.qualification,
    this.gender,
    this.languages,
    this.city,
    this.fromDate,
    this.toDate,
    this.sort = 'created_at',
    this.order = 'desc',
    this.page = 1,
    this.limit = 20,
  });

  Map<String, dynamic> toQueryParameters() {
    return {
      'page': page,
      'limit': limit,
      'sort': sort,
      'order': order,
      if (search != null && search!.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
      if (qualification != null) 'qualification': qualification,
      if (gender != null) 'gender': gender,
      if (languages != null && languages!.isNotEmpty)
        'language': languages!.join(','),
      if (city != null) 'city': city,
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
    };
  }
}

class CaregiverListResult {
  final List<AdminCaregiverListItem> items;
  final PaginationMeta meta;

  const CaregiverListResult({required this.items, required this.meta});
}

class AdminCaregiversRepository {
  final Dio _dio;

  AdminCaregiversRepository(this._dio);

  Future<CaregiverListResult> list(CaregiverListFilters filters) async {
    try {
      final res = await _dio.get('/admin/caregivers',
          queryParameters: filters.toQueryParameters());
      final items = (res.data['data'] as List)
          .map((json) =>
              AdminCaregiverListItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta =
          PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return CaregiverListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AdminCaregiverDetail> getDetail(String profileId) async {
    try {
      final res = await _dio.get('/admin/caregivers/$profileId');
      return AdminCaregiverDetail.fromJson(
          res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> updateStatus(String profileId, String status,
      {String? rejectionMessage}) async {
    try {
      final res = await _dio.patch(
        '/admin/caregivers/$profileId/status',
        data: {
          'status': status,
          if (rejectionMessage != null) 'rejection_message': rejectionMessage
        },
      );
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> upsertNotes(
    String profileId, {
    String? internalNotes,
    String? availabilityRemarks,
  }) async {
    try {
      await _dio.post(
        '/admin/caregivers/$profileId/notes',
        data: {
          'internal_notes': internalNotes,
          'availability_remarks': availabilityRemarks,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Any subset of fields — only non-null entries in [fields] are sent.
  Future<void> editProfile(
      String profileId, Map<String, dynamic> fields) async {
    try {
      await _dio.put('/admin/caregivers/$profileId', data: fields);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Uses MultipartFile.fromBytes (not .fromFile) — this app is Flutter Web
  /// only, which has no filesystem path to give dio.
  Future<String> uploadSelfie(
      String profileId, Uint8List bytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post('/admin/caregivers/$profileId/selfie',
          data: formData);
      return res.data['data']['file_path'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> uploadDocument(
    String profileId,
    Uint8List bytes,
    String filename,
    String documentType,
  ) async {
    try {
      final formData = FormData.fromMap({
        'document_type': documentType,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post('/admin/caregivers/$profileId/documents',
          data: formData);
      return res.data['data']['file_path'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
