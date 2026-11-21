import '../constants/validation.dart';

/// One feedback: 1-5 stars and an optional short comment. Overall for a whole
/// engagement (one caregiver on one job), never per salary cycle.
class FeedbackModel {
  final int rating;
  final String? comment;
  final String? createdAt;

  const FeedbackModel({required this.rating, this.comment, this.createdAt});

  factory FeedbackModel.fromJson(Map<String, dynamic> json) => FeedbackModel(
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: json['created_at'] as String?,
      );

  /// Tolerant parse for the optional `my_feedback` / `their_feedback` fields.
  static FeedbackModel? tryParse(Object? json) =>
      json is Map<String, dynamic> ? FeedbackModel.fromJson(json) : null;
}

/// What GET .../feedback returns for the signed-in person on one engagement.
class FeedbackState {
  /// True while they may still write one (the work has started and they have not written yet).
  final bool canGive;
  /// True when they wrote one and may still change it (patients/families only).
  final bool canEdit;
  /// 'not_started' or 'no_family_account' when [canGive] is false and nothing was written.
  final String? reason;
  final FeedbackModel? mine;
  final FeedbackModel? received;

  const FeedbackState({required this.canGive, this.canEdit = false, this.reason, this.mine, this.received});

  factory FeedbackState.fromJson(Map<String, dynamic> json) => FeedbackState(
        canGive: json['can_give'] as bool? ?? false,
        canEdit: json['can_edit'] as bool? ?? false,
        reason: json['reason'] as String?,
        mine: FeedbackModel.tryParse(json['mine']),
        received: FeedbackModel.tryParse(json['received']),
      );
}

/// Whether the work has started, judged from fields the apps already have: the
/// caregiver was accepted and the agreed cycle start date (YYYY-MM-DD) has arrived.
/// Only decides whether to SHOW the "leave feedback" button; the server enforces it.
/// [acceptedAt] is any non-empty value when accepted.
bool feedbackEligible({required String? acceptedAt, required String? agreedStartDate, DateTime? today}) {
  if (acceptedAt == null || agreedStartDate == null) return false;
  final start = DateTime.tryParse(agreedStartDate);
  if (start == null) return false;
  final now = today ?? DateTime.now();
  final startDay = DateTime(start.year, start.month, start.day);
  final todayDay = DateTime(now.year, now.month, now.day);
  return !startDay.isAfter(todayDay);
}

/// Trims [text]; null when empty, and never longer than the allowed comment length.
String? cleanFeedbackComment(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > Validation.feedbackCommentMaxLength
      ? trimmed.substring(0, Validation.feedbackCommentMaxLength)
      : trimmed;
}
