import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import 'admin_caregiver_models.dart';

class CaregiverListFilters {
  final String? search;
  final String? status;
  final String? qualification;
  final List<String>? languages;
  final String? serviceMode;
  final String? workType;
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
    this.languages,
    this.serviceMode,
    this.workType,
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
      if (languages != null && languages!.isNotEmpty) 'language': languages!.join(','),
      if (serviceMode != null) 'service_mode': serviceMode,
      if (workType != null) 'work_type': workType,
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
      final res = await _dio.get('/admin/caregivers', queryParameters: filters.toQueryParameters());
      final items = (res.data['data'] as List)
          .map((json) => AdminCaregiverListItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return CaregiverListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AdminCaregiverDetail> getDetail(String profileId) async {
    try {
      final res = await _dio.get('/admin/caregivers/$profileId');
      return AdminCaregiverDetail.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> markCallVerified(String profileId) async {
    try {
      final res = await _dio.patch('/admin/caregivers/$profileId/call-verified');
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> updateStatus(String profileId, String status, {String? rejectionMessage}) async {
    try {
      final res = await _dio.patch(
        '/admin/caregivers/$profileId/status',
        data: {'status': status, if (rejectionMessage != null) 'rejection_message': rejectionMessage},
      );
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> upsertNotes(
    String profileId, {
    String? internalNotes,
    num? rate24hrsLiveIn,
    num? rate12hrsPg,
    String? availabilityRemarks,
  }) async {
    try {
      await _dio.post(
        '/admin/caregivers/$profileId/notes',
        data: {
          'internal_notes': internalNotes,
          'rate_24hrs_live_in': rate24hrsLiveIn,
          'rate_12hrs_pg': rate12hrsPg,
          'availability_remarks': availabilityRemarks,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Any subset of fields — only non-null entries in [fields] are sent.
  /// Does NOT include service_modes/work_types/salary; use the dedicated
  /// methods below for those.
  Future<void> editProfile(String profileId, Map<String, dynamic> fields) async {
    try {
      await _dio.put('/admin/caregivers/$profileId', data: fields);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<String>> assignWorkTypes(String profileId, List<String> workTypes) async {
    try {
      final res = await _dio.put(
        '/admin/caregivers/$profileId/work-types',
        data: {'work_types': workTypes},
      );
      return List<String>.from(res.data['data']['work_types'] as List);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<String>> assignServiceModes(String profileId, List<String> serviceModes) async {
    try {
      final res = await _dio.put(
        '/admin/caregivers/$profileId/service-modes',
        data: {'service_modes': serviceModes},
      );
      return List<String>.from(res.data['data']['service_modes'] as List);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<num> updateSalary(String profileId, num salary) async {
    try {
      final res = await _dio.patch('/admin/caregivers/$profileId/salary', data: {'salary': salary});
      return res.data['data']['salary'] as num;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Uses MultipartFile.fromBytes (not .fromFile) — this app is Flutter Web
  /// only, which has no filesystem path to give dio.
  Future<String> uploadSelfie(String profileId, Uint8List bytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post('/admin/caregivers/$profileId/selfie', data: formData);
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
      final res = await _dio.post('/admin/caregivers/$profileId/documents', data: formData);
      return res.data['data']['file_path'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
