import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// A single tip row shown in the bell overlay — pairs the message text with
/// an icon so each row reads as its own category at a glance, not an
/// undifferentiated stack of paragraphs that all look the same. [id] is the
/// backing CaregiverMessageModel's id — used by MessagesBellButton to track
/// which templates the user has already seen (see LocalStorage's
/// readMessageIds/markMessagesRead).
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

/// Replaces the literal token "{job_id}" with [job]'s display id — safe to
/// call on any message (a no-op if the token isn't present).
String _interpolate(String message, JobModel job) {
  if (!message.contains('{job_id}')) return message;
  return message.replaceAll('{job_id}', jobDisplayId(job));
}

/// Picks the most recently relevant job for [event] out of [activeJobs] +
/// [assignedJobs] — whichever job has the latest matching timestamp for
/// that event's status transition. Returns null if no job currently
/// matches the event.
JobModel? _mostRecentMatch(
  String event,
  List<JobModel> activeJobs,
  List<JobModel> assignedJobs,
) {
  JobModel? best;
  String? bestTimestamp;

  void consider(JobModel job, String? timestamp) {
    if (timestamp == null) return;
    if (bestTimestamp == null || timestamp.compareTo(bestTimestamp!) > 0) {
      best = job;
      bestTimestamp = timestamp;
    }
  }

  switch (event) {
    case CaregiverMessageEvent.jobApplied:
      for (final job in activeJobs) {
        if (job.myApplication?.status == JobApplicationStatus.applied) {
          consider(job, job.myApplication!.appliedAt);
        }
      }
      break;
    case CaregiverMessageEvent.jobRejected:
      for (final job in activeJobs) {
        if (job.myApplication?.status == JobApplicationStatus.rejected) {
          consider(job, job.myApplication!.rejectedAt);
        }
      }
      break;
    case CaregiverMessageEvent.jobAccepted:
      for (final job in assignedJobs) {
        if (job.myApplication?.status == JobApplicationStatus.accepted) {
          consider(job, job.myApplication!.acceptedAt);
        }
      }
      break;
    case CaregiverMessageEvent.jobClosed:
      for (final job in assignedJobs) {
        if (job.myApplication?.status == JobApplicationStatus.completed) {
          consider(job, job.myApplication!.completedAt);
        }
      }
      break;
  }

  return best;
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
/// applied to any job. jobApplied/jobRejected are only detectable while the
/// underlying job stays active (no "full application history" endpoint
/// exists — see caregiver-messages plan doc); jobAccepted/jobClosed are
/// fully durable via the assigned endpoint. All applicable templates —
/// regardless of which event matched — are sorted together by a single
/// shared displayOrder, so admin fully controls how they interleave.
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

  final applicable = <CaregiverMessageModel>[];
  final matches = <String, JobModel?>{};

  for (final t in templates) {
    if (t.event == CaregiverMessageEvent.welcome) continue;
    final match = _mostRecentMatch(t.event, activeJobs, assignedJobs);
    if (match != null) {
      applicable.add(t);
      matches[t.id] = match;
    }
  }

  applicable.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  return applicable
      .map((t) => CaregiverMessageItem(t.id, iconFor(t.icon), _interpolate(t.message, matches[t.id]!)))
      .toList();
}
