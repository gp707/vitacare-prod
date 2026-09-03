/// Mirrors one row of the `GET /individual-messages` / `GET /admin/
/// individual-messages` response — a single admin-editable tip shown on
/// NurseNow Individual's Messages tab. [event] (see MessageEvent) decides
/// when it's shown; [message] may contain the literal token "{tier}" when
/// [event] is MessageEvent.requirementCareTier, substituted client-side
/// with the derived care tier's display name (see
/// resolveMessages()/interpolate() in apps/nursenow-app/lib/features/
/// individual/data/requirement_messages.dart).
class IndividualMessageModel {
  final String id;
  final String event;
  final String icon;
  final String message;
  final int displayOrder;
  final bool enabled;

  const IndividualMessageModel({
    required this.id,
    required this.event,
    required this.icon,
    required this.message,
    required this.displayOrder,
    required this.enabled,
  });

  factory IndividualMessageModel.fromJson(Map<String, dynamic> json) => IndividualMessageModel(
        id: json['id'] as String,
        event: json['event'] as String,
        icon: json['icon'] as String,
        message: json['message'] as String,
        displayOrder: json['display_order'] as int,
        enabled: json['enabled'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'event': event,
        'icon': icon,
        'message': message,
        'display_order': displayOrder,
        'enabled': enabled,
      };
}
