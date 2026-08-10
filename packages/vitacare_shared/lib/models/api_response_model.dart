/// Mirrors the API's response envelope (SPEC.md section 6.2):
/// success: { success: true, data, meta? }
/// error:   { success: false, error: { code, message } }
class ApiError {
  final String code;
  final String message;

  const ApiError({required this.code, required this.message});

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
        code: json['code'] as String,
        message: json['message'] as String,
      );
}

class PaginationMeta {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const PaginationMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) => PaginationMeta(
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
        totalPages: json['totalPages'] as int,
      );
}

/// [data] is the raw decoded JSON for the `data` field on success; callers
/// parse it into a concrete model. Null (with [error] set) on failure.
class ApiResponse {
  final bool success;
  final dynamic data;
  final PaginationMeta? meta;
  final ApiError? error;

  const ApiResponse({
    required this.success,
    this.data,
    this.meta,
    this.error,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    final success = json['success'] as bool;
    return ApiResponse(
      success: success,
      data: success ? json['data'] : null,
      meta: json['meta'] != null
          ? PaginationMeta.fromJson(json['meta'] as Map<String, dynamic>)
          : null,
      error: !success
          ? ApiError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
}
