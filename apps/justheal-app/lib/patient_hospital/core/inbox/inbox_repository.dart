import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// The alerts under the bell (see UserNotificationModel). Needs the person to be signed in.
class InboxRepository {
  final Dio _dio;

  InboxRepository(this._dio);

  /// Unread alerts under 2 days old, newest first.
  Future<List<UserNotificationModel>> list() async {
    final res = await _dio.get(ApiRoutes.notifications);
    return (res.data['data'] as List)
        .map((json) => UserNotificationModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Reading an alert takes it off the bell for good.
  Future<void> markRead(String id) async {
    await _dio.patch(ApiRoutes.notificationRead(id));
  }
}
