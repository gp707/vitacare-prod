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
    case MessageIcon.personAdd:
      return Icons.person_add;
    case MessageIcon.checkCircle:
      return Icons.check_circle;
    case MessageIcon.cancel:
      return Icons.cancel;
    case MessageIcon.taskAlt:
      return Icons.task_alt;
    case MessageIcon.info:
    default:
      return Icons.info;
  }
}

bool _isLive(JobModel requirement) =>
    requirement.status == JobStatus.pendingReview || requirement.status == JobStatus.active;

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
/// Messages tab load) against the individual's own [requirements] and
/// [currentRequirementApplications] (the applications on the most
/// recently posted requirement — see [needsApplicationsFetch]) into the
/// final ordered list to render — no persistence, no read/unread state,
/// recomputed fresh every time, same architecture as before this became
/// admin-editable, just data-driven now instead of hardcoded.
///
/// Before the account has ever posted a requirement at all, only
/// MessageEvent.welcome templates apply. Otherwise every other event is
/// evaluated against `requirements.first` — the account's most recently
/// posted requirement (the backend returns requirements newest-first) —
/// since acceptance closes a requirement (flips it off "live"), so a
/// caregiverAccepted/caregiverClosed tip can never coexist with that same
/// requirement still being "live"; picking the single most recent
/// requirement, regardless of its exact status, is what lets both still
/// work without tracking two different "current requirement" concepts.
/// requirementLive/requirementCareTier still require that requirement to
/// actually be live; the 4 caregiver_* events instead check whether an
/// application with the matching status is present on it (not mutually
/// exclusive with each other or with requirementLive — e.g. a still-live
/// requirement can simultaneously have other applied-but-undecided
/// candidates). All applicable templates — regardless of which event
/// matched — are sorted together by a single shared displayOrder, so
/// admin fully controls how they interleave.
List<MessageItem> resolveMessages(
  List<IndividualMessageModel> templates,
  List<JobModel> requirements,
  List<JobApplicationModel> currentRequirementApplications,
) {
  if (requirements.isEmpty) {
    final welcome = templates.where((t) => t.event == MessageEvent.welcome).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return welcome.map((t) => MessageItem(iconFor(t.icon), t.message)).toList();
  }

  final current = requirements.first;
  final applicationStatuses = currentRequirementApplications.map((a) => a.status).toSet();

  final applicable = templates.where((t) {
    switch (t.event) {
      case MessageEvent.requirementLive:
        return _isLive(current);
      case MessageEvent.requirementCareTier:
        return _isLive(current) && current.careReceiver != null;
      case MessageEvent.caregiverApplied:
        return applicationStatuses.contains(JobApplicationStatus.applied);
      case MessageEvent.caregiverAccepted:
        return applicationStatuses.contains(JobApplicationStatus.accepted);
      case MessageEvent.caregiverRejected:
        return applicationStatuses.contains(JobApplicationStatus.rejected);
      case MessageEvent.caregiverClosed:
        return applicationStatuses.contains(JobApplicationStatus.completed);
      default:
        return false;
    }
  }).toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  return applicable.map((t) => MessageItem(iconFor(t.icon), _interpolate(t.message, current))).toList();
}

/// Whether resolveMessages() needs applications data for [requirements] at
/// all — false when there's nothing posted yet, or when the most recent
/// requirement is still pending_review (caregivers can't see/apply to a
/// job before it's approved to active, so it's guaranteed to have zero
/// applications — fetching would just waste a network call).
bool needsApplicationsFetch(List<JobModel> requirements) =>
    requirements.isNotEmpty && requirements.first.status != JobStatus.pendingReview;
