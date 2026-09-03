import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// A single tip row on the Messages tab — pairs the message text with an
/// icon so each row reads as its own category at a glance, not an
/// undifferentiated stack of paragraphs that all look the same.
class MessageItem {
  final IconData icon;
  final String text;

  const MessageItem(this.icon, this.text);
}

/// Maps an admin-picked MessageIcon key to real IconData — a fixed,
/// bounded switch (never free-form), so a bad/future-unknown key falls
/// back to a neutral default instead of crashing.
IconData iconFor(String key) {
  switch (key) {
    case MessageIcon.editNote:
      return Icons.edit_note;
    case MessageIcon.rule:
      return Icons.rule;
    case MessageIcon.travelExplore:
      return Icons.travel_explore;
    case MessageIcon.wavingHand:
      return Icons.waving_hand;
    case MessageIcon.rocketLaunch:
      return Icons.rocket_launch;
    case MessageIcon.favorite:
      return Icons.favorite;
    case MessageIcon.medicalServices:
      return Icons.medical_services;
    case MessageIcon.emergency:
      return Icons.emergency;
    case MessageIcon.celebration:
      return Icons.celebration;
    case MessageIcon.info:
    default:
      return Icons.info;
  }
}

bool _isLive(JobModel requirement) =>
    requirement.status == JobStatus.pendingReview || requirement.status == JobStatus.active;

/// At most one requirement is ever live at a time (the existing one-live-
/// requirement rule, JOB_009), so the first live one found is the only one
/// that matters here.
JobModel? _liveRequirement(List<JobModel> requirements) {
  for (final requirement in requirements) {
    if (_isLive(requirement)) return requirement;
  }
  return null;
}

/// Replaces the literal token "{tier}" with the derived care tier's
/// display name — only meaningful for MessageEvent.requirementCareTier
/// messages, but safe to call on any message (a no-op if the token isn't
/// present or there's no care receiver to derive a tier from).
String _interpolate(String message, JobModel requirement) {
  if (!message.contains('{tier}')) return message;
  final careReceiver = requirement.careReceiver;
  if (careReceiver == null) return message;
  final tier = deriveCareTier(careReceiver);
  final tierLabel = CareTier.displayNames[tier] ?? tier;
  return message.replaceAll('{tier}', tierLabel);
}

/// Resolves [templates] (the full admin-editable set, fetched once per
/// Messages tab load) against the individual's own [requirements] into the
/// final ordered list to render — no persistence, no read/unread state,
/// recomputed fresh every time, same architecture as before this became
/// admin-editable, just data-driven now instead of hardcoded.
///
/// Before the account has ever posted a requirement at all, only
/// MessageEvent.welcome templates apply. Otherwise, only the one
/// currently-live requirement (if any) matters: MessageEvent.
/// requirementLive templates always apply, and MessageEvent.
/// requirementCareTier templates apply additionally when that requirement
/// has a care_receiver. All applicable templates — regardless of which
/// event matched — are sorted together by a single shared displayOrder,
/// so admin fully controls how they interleave.
List<MessageItem> resolveMessages(List<IndividualMessageModel> templates, List<JobModel> requirements) {
  if (requirements.isEmpty) {
    final welcome = templates.where((t) => t.event == MessageEvent.welcome).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return welcome.map((t) => MessageItem(iconFor(t.icon), t.message)).toList();
  }

  final live = _liveRequirement(requirements);
  if (live == null) return const [];

  final applicable = templates.where((t) {
    if (t.event == MessageEvent.requirementLive) return true;
    if (t.event == MessageEvent.requirementCareTier) return live.careReceiver != null;
    return false;
  }).toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  return applicable.map((t) => MessageItem(iconFor(t.icon), _interpolate(t.message, live))).toList();
}
