import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// A single tip row shown in the bell overlay — pairs the message text with
/// an icon so each row reads as its own category at a glance, not an
/// undifferentiated stack of paragraphs that all look the same. [id] is
/// `"<template id>:<job id>"` for a job-scoped event (jobApplied/
/// jobAccepted/jobRejected/jobClosed fire once per matching job
/// application, not just once for the most recent one — see
/// resolveCaregiverMessages) or the bare template id for `welcome`, which
/// isn't job-scoped. Used by MessagesBellButton to track which (template,
/// job) pairs the user has already seen (see LocalStorage's
/// readMessageIds/markMessagesRead) — composite so marking one job's
/// "applied" message read doesn't also mark a different job's read.
class CaregiverMessageItem {
  final String id;
  final IconData icon;
  final String text;

  const CaregiverMessageItem(this.id, this.icon, this.text);
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

/// Replaces the token `{job_id}` (the documented format — see admin-web's
/// helper text) with [job]'s display id — safe to call on any message (a
/// no-op if neither token is present). Also accepts `<job_id>` as a
/// tolerated alternative, since admin free-typing the message field has no
/// enforced syntax and angle brackets are a common way people denote a
/// placeholder — silently supporting both means a stray typo doesn't
/// quietly ship a message with the literal token still showing.
String _interpolate(String message, JobModel job) {
  var result = message;
  if (result.contains('{job_id}')) {
    result = result.replaceAll('{job_id}', jobDisplayId(job));
  }
  if (result.contains('<job_id>')) {
    result = result.replaceAll('<job_id>', jobDisplayId(job));
  }
  return result;
}

/// One job whose application currently matches an event, paired with the
/// timestamp of that transition (used only to order same-template matches
/// newest-first — never shown to the user).
class _JobMatch {
  final JobModel job;
  final String? timestamp;

  const _JobMatch(this.job, this.timestamp);
}

/// Every job out of [activeJobs] + [assignedJobs] whose application
/// currently matches [event] — one entry per job, not just the most
/// recent, since each job application fires its own message instance (a
/// caregiver who applied to 3 jobs sees 3 "applied" messages, each with
/// that job's own real id).
List<_JobMatch> _allMatches(
  String event,
  List<JobModel> activeJobs,
  List<JobModel> assignedJobs,
) {
  final matches = <_JobMatch>[];

  switch (event) {
    case CaregiverMessageEvent.jobApplied:
      for (final job in activeJobs) {
        if (job.myApplication?.status == JobApplicationStatus.applied) {
          matches.add(_JobMatch(job, job.myApplication!.appliedAt));
        }
      }
      break;
    case CaregiverMessageEvent.jobRejected:
      for (final job in activeJobs) {
        if (job.myApplication?.status == JobApplicationStatus.rejected) {
          matches.add(_JobMatch(job, job.myApplication!.rejectedAt));
        }
      }
      break;
    case CaregiverMessageEvent.jobAccepted:
      for (final job in assignedJobs) {
        if (job.myApplication?.status == JobApplicationStatus.accepted) {
          matches.add(_JobMatch(job, job.myApplication!.acceptedAt));
        }
      }
      break;
    case CaregiverMessageEvent.jobClosed:
      for (final job in assignedJobs) {
        if (job.myApplication?.status == JobApplicationStatus.completed) {
          matches.add(_JobMatch(job, job.myApplication!.completedAt));
        }
      }
      break;
  }

  return matches;
}

/// Whether the caregiver has ever applied to any job — checked across both
/// [activeJobs] (currently-active jobs, each possibly carrying
/// myApplication) and [assignedJobs] (durable accepted/completed history
/// regardless of the job's own status), since a job can leave the active
/// list (close for an unrelated reason) while still being the caregiver's
/// only-ever application.
bool _hasEverApplied(List<JobModel> activeJobs, List<JobModel> assignedJobs) =>
    activeJobs.any((j) => j.myApplication != null) || assignedJobs.isNotEmpty;

/// Resolves [templates] (the full admin-editable set, fetched once per
/// Messages bell load) against the caregiver's own [activeJobs] (from
/// GET /caregiver/jobs) and [assignedJobs] (from GET /caregiver/jobs/
/// assigned) into the final ordered list to render — no persistence, no
/// read/unread state, recomputed fresh every time.
///
/// CaregiverMessageEvent.welcome only applies before the caregiver has ever
/// applied to any job. Every other event fires **once per matching job
/// application**, not just once for the most recently matching job — a
/// caregiver who has applied to 3 jobs sees 3 separate "applied" messages,
/// each with that job's own real display id substituted for `{job_id}`.
/// jobApplied/jobRejected are only detectable while the underlying job
/// stays active (no "full application history" endpoint exists — see
/// caregiver-messages plan doc); jobAccepted/jobClosed are fully durable
/// via the assigned endpoint. Every item — regardless of which
/// template/job matched — is sorted by the template's shared displayOrder
/// first (so admin fully controls how different events interleave), then
/// by that job's own transition timestamp newest-first as a tie-break
/// among multiple jobs sharing one template.
List<CaregiverMessageItem> resolveCaregiverMessages(
  List<CaregiverMessageModel> templates,
  List<JobModel> activeJobs,
  List<JobModel> assignedJobs,
) {
  if (!_hasEverApplied(activeJobs, assignedJobs)) {
    final welcome = templates.where((t) => t.event == CaregiverMessageEvent.welcome).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return welcome.map((t) => CaregiverMessageItem(t.id, iconFor(t.icon), t.message)).toList();
  }

  final entries = <(CaregiverMessageModel template, _JobMatch match)>[];

  for (final t in templates) {
    if (t.event == CaregiverMessageEvent.welcome) continue;
    for (final match in _allMatches(t.event, activeJobs, assignedJobs)) {
      entries.add((t, match));
    }
  }

  entries.sort((a, b) {
    final orderCompare = a.$1.displayOrder.compareTo(b.$1.displayOrder);
    if (orderCompare != 0) return orderCompare;
    return (b.$2.timestamp ?? '').compareTo(a.$2.timestamp ?? '');
  });

  return entries
      .map((e) => CaregiverMessageItem(
            '${e.$1.id}:${e.$2.job.id}',
            iconFor(e.$1.icon),
            _interpolate(e.$1.message, e.$2.job),
          ))
      .toList();
}
