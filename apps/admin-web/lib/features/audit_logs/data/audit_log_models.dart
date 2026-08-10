export 'package:vitacare_shared/vitacare_shared.dart' show PaginationMeta;

class AuditLogEntry {
  final String id;
  final String? userId;
  final String? userName;
  final String? targetUserId;
  final String? targetUserName;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? beforeValue;
  final Map<String, dynamic>? afterValue;
  final String? ipAddress;
  final String createdAt;

  const AuditLogEntry({
    required this.id,
    this.userId,
    this.userName,
    this.targetUserId,
    this.targetUserName,
    required this.action,
    required this.entityType,
    this.entityId,
    this.beforeValue,
    this.afterValue,
    this.ipAddress,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        userId: json['user_id'] as String?,
        userName: json['user_name'] as String?,
        targetUserId: json['target_user_id'] as String?,
        targetUserName: json['target_user_name'] as String?,
        action: json['action'] as String,
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as String?,
        beforeValue: json['before_value'] as Map<String, dynamic>?,
        afterValue: json['after_value'] as Map<String, dynamic>?,
        ipAddress: json['ip_address'] as String?,
        createdAt: json['created_at'] as String,
      );
}
