import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// A single tip row shown in the bell overlay — pairs the message text with
/// an icon so each row reads as its own category at a glance, not an
/// undifferentiated stack of paragraphs that all look the same. [id] is
/// `"<template id>:<application id>"` for an applicant-scoped event
/// (caregiverApplied/caregiverAccepted/caregiverRejected/caregiverClosed
/// fire once per matching applicant, not just once for the whole
/// requirement — see resolveMessages) or the bare template id for
/// welcome/requirementLive/requirementCareTier, which aren't
/// applicant-scoped. Used by MessagesBellButton to track which (template,
/// applicant) pairs the user has already seen (see LocalStorage's
/// readMessageIds/markMessagesRead) — composite so marking one applicant's
/// "applied" message read doesn't also mark a different applicant's read.
class MessageItem {
  final String id;
  final IconData icon;
  final String text;

  const MessageItem(this.id, this.icon, this.text);
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

/// Replaces `{tier}` with the derived care tier's display name (only
/// meaningful for MessageEvent.requirementCareTier) and `{caregiver_name}`
/// with [application]'s applicant name (only meaningful for the 4
/// applicant-scoped caregiver_* events) — safe to call on any message, a
/// no-op for whichever token isn't present or whose source data is absent.
/// `<tier>`/`<caregiver_name>` are also tolerated alongside the documented
/// curly-brace form, since admin free-typing the message field has no
/// enforced syntax and angle brackets are a common way people denote a
/// placeholder — silently supporting both means a stray typo doesn't
/// quietly ship a message with the literal token still showing.
String _interpolate(String message, JobModel requirement, {JobApplicationModel? application}) {
  var result = message;
  if (result.contains('{tier}') || result.contains('<tier>')) {
    final careReceiver = requirement.careReceiver;
    if (careReceiver != null) {
      final tier = deriveCareTier(careReceiver);
      final tierLabel = CareTier.displayNames[tier] ?? tier;
      result = result.replaceAll('{tier}', tierLabel).replaceAll('<tier>', tierLabel);
    }
  }
  if (application != null) {
    result = result.replaceAll('{caregiver_name}', application.fullName).replaceAll('<caregiver_name>', application.fullName);
  }
  return result;
}

/// Every application out of [applications] that currently matches
/// [event], paired with the timestamp of that transition (used only to
/// order same-template matches newest-first — never shown to the user).
/// One entry per matching applicant, not just the most recent, since each
/// applicant fires their own message instance (a requirement with 3
/// applicants sees 3 "applied" messages, each naming that applicant).
List<(JobApplicationModel application, String? timestamp)> _matchingApplications(
  String event,
  List<JobApplicationModel> applications,
) {
  switch (event) {
    case MessageEvent.caregiverApplied:
      return applications
          .where((a) => a.status == JobApplicationStatus.applied)
          .map((a) => (a, a.appliedAt))
          .toList();
    case MessageEvent.caregiverAccepted:
      return applications
          .where((a) => a.status == JobApplicationStatus.accepted)
          .map((a) => (a, a.acceptedAt))
          .toList();
    case MessageEvent.caregiverRejected:
      return applications
          .where((a) => a.status == JobApplicationStatus.rejected)
          .map((a) => (a, a.rejectedAt))
          .toList();
    case MessageEvent.caregiverClosed:
      return applications
          .where((a) => a.status == JobApplicationStatus.completed)
          .map((a) => (a, a.completedAt))
          .toList();
    default:
      return const [];
  }
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
/// actually be live and each fire at most once. The 4 caregiver_* events
/// instead fire **once per matching applicant** — a requirement with 3
/// still-undecided applicants shows 3 separate "applied" messages, each
/// with that applicant's own real name substituted for
/// `{caregiver_name}` — not mutually exclusive with each other or with
/// requirementLive (e.g. a still-live requirement can simultaneously have
/// other applied-but-undecided candidates). Every item — regardless of
/// which template/applicant matched — is sorted by the template's shared
/// displayOrder first (so admin fully controls how different events
/// interleave), then by that applicant's own transition timestamp
/// newest-first as a tie-break among multiple applicants sharing one
/// template.
List<MessageItem> resolveMessages(
  List<IndividualMessageModel> templates,
  List<JobModel> requirements,
  List<JobApplicationModel> currentRequirementApplications,
) {
  if (requirements.isEmpty) {
    final welcome = templates.where((t) => t.event == MessageEvent.welcome).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return welcome.map((t) => MessageItem(t.id, iconFor(t.icon), t.message)).toList();
  }

  final current = requirements.first;

  final entries = <(IndividualMessageModel template, JobApplicationModel? application, String? timestamp)>[];

  for (final t in templates) {
    switch (t.event) {
      case MessageEvent.requirementLive:
        if (_isLive(current)) entries.add((t, null, null));
        break;
      case MessageEvent.requirementCareTier:
        if (_isLive(current) && current.careReceiver != null) entries.add((t, null, null));
        break;
      case MessageEvent.caregiverApplied:
      case MessageEvent.caregiverAccepted:
      case MessageEvent.caregiverRejected:
      case MessageEvent.caregiverClosed:
        for (final (application, timestamp) in _matchingApplications(t.event, currentRequirementApplications)) {
          entries.add((t, application, timestamp));
        }
        break;
    }
  }

  entries.sort((a, b) {
    final orderCompare = a.$1.displayOrder.compareTo(b.$1.displayOrder);
    if (orderCompare != 0) return orderCompare;
    return (b.$3 ?? '').compareTo(a.$3 ?? '');
  });

  return entries
      .map((e) => MessageItem(
            e.$2 == null ? e.$1.id : '${e.$1.id}:${e.$2!.id}',
            iconFor(e.$1.icon),
            _interpolate(e.$1.message, current, application: e.$2),
          ))
      .toList();
}

/// Whether resolveMessages() needs applications data for [requirements] at
/// all — false when there's nothing posted yet, or when the most recent
/// requirement is still pending_review (caregivers can't see/apply to a
/// job before it's approved to active, so it's guaranteed to have zero
/// applications — fetching would just waste a network call).
bool needsApplicationsFetch(List<JobModel> requirements) =>
    requirements.isNotEmpty && requirements.first.status != JobStatus.pendingReview;
