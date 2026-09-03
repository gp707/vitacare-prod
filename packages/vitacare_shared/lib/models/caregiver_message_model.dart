/// Mirrors one row of the `GET /caregiver-messages` / `GET /admin/
/// caregiver-messages` response — a single admin-editable tip shown on
/// NurseJobs (caregiver-app)'s Messages bell. [event] (see
/// CaregiverMessageEvent) decides when it's shown; [message] may contain
/// the literal token "{job_id}", substituted client-side with the relevant
/// job's display id (see resolveCaregiverMessages()/interpolate() in
/// apps/caregiver-app/lib/features/jobs/data/caregiver_messages_logic.dart).
class CaregiverMessageModel {
  final String id;
  final String event;
  final String icon;
  final String message;
  final int displayOrder;
  final bool enabled;

  const CaregiverMessageModel({
    required this.id,
    required this.event,
    required this.icon,
    required this.message,
    required this.displayOrder,
    required this.enabled,
  });

  factory CaregiverMessageModel.fromJson(Map<String, dynamic> json) => CaregiverMessageModel(
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
