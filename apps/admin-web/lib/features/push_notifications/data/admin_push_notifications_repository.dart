import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminPushNotificationItem {
  final String id;
  final String createdByName;
  final String title;
  final String body;
  final String scheduledAt;
  final String? sentAt;
  final String status;
  final int recipientCount;
  final String createdAt;

  const AdminPushNotificationItem({
    required this.id,
    required this.createdByName,
    required this.title,
    required this.body,
    required this.scheduledAt,
    this.sentAt,
    required this.status,
    required this.recipientCount,
    required this.createdAt,
  });

  factory AdminPushNotificationItem.fromJson(Map<String, dynamic> json) =>
      AdminPushNotificationItem(
        id: json['id'] as String,
        createdByName: json['created_by_name'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        scheduledAt: json['scheduled_at'] as String,
        sentAt: json['sent_at'] as String?,
        status: json['status'] as String,
        recipientCount: json['recipient_count'] as int,
        createdAt: json['created_at'] as String,
      );
}

class AdminPushNotificationsListResult {
  final List<AdminPushNotificationItem> items;
  final PaginationMeta meta;

  const AdminPushNotificationsListResult({required this.items, required this.meta});
}

class AdminPushNotificationsRepository {
  final Dio _dio;

  AdminPushNotificationsRepository(this._dio);

  /// [scheduledAt] null (or already in the past) sends immediately — the
  /// response's own `status` then reflects whether it actually went out
  /// ('sent') or not ('failed'), not just an optimistic "queued".
  /// Otherwise it's queued server-side for that future date/time.
  Future<AdminPushNotificationItem> create({
    required String title,
    required String body,
    DateTime? scheduledAt,
    required List<String> recipientUserIds,
  }) async {
    try {
      final res = await _dio.post('/admin/push-notifications', data: {
        'title': title,
        'body': body,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'recipient_user_ids': recipientUserIds,
      });
      return AdminPushNotificationItem.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AdminPushNotificationsListResult> list({int page = 1, int limit = 20}) async {
    try {
      final res = await _dio.get('/admin/push-notifications', queryParameters: {
        'page': page,
        'limit': limit,
      });
      final items = (res.data['data'] as List)
          .map((item) => AdminPushNotificationItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminPushNotificationsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Only a still-pending, future-scheduled notification can be cancelled
  /// — the backend 400s (PUSH_001) otherwise.
  Future<void> cancel(String id) async {
    try {
      await _dio.patch('/admin/push-notifications/$id/cancel');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
