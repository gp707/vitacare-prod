/// One alert kept under a person's bell (`GET /notifications`): a push they were sent, stored so it
/// can be read later. It leaves the bell once read or after 2 days, whichever comes first.
class UserNotificationModel {
  final String id;
  final String title;
  final String body;

  /// The screen the push opens (e.g. `/home`), when it has one.
  final String? route;
  final DateTime? createdAt;

  const UserNotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.route,
    this.createdAt,
  });

  factory UserNotificationModel.fromJson(Map<String, dynamic> json) => UserNotificationModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        route: json['route'] as String?,
        createdAt: json['created_at'] == null ? null : DateTime.tryParse(json['created_at'] as String),
      );

  /// What the bell shows as one line: the title, then the message.
  String get text => title.isEmpty ? body : (body.isEmpty ? title : '$title — $body');
}
