import 'package:vitacare_shared/vitacare_shared.dart';

/// Automatic, status-based tips shown on the Individual's "Messages" tab —
/// purely computed client-side from a requirement's current fields (no
/// backend model, no persistence, no read/unread state). Always reflects
/// whatever the requirement's current status/care needs are right now,
/// recomputed fresh every time the tab is opened — there's no dedup or
/// "already shown" tracking, so the "everyday" cadence on the last message
/// below just means it keeps appearing every day the job stays live, not a
/// literal once-per-calendar-day flag.
///
/// Returns every message that currently applies to [requirement], in a
/// fixed logical order — not a real timeline, since none of these are
/// one-off events with their own timestamp. Empty once the requirement is
/// no longer live (closed/rejected/cancelled) — a past requirement has
/// nothing left to advise the patient/family about.
List<String> messagesForRequirement(JobModel requirement) {
  final isLive = requirement.status == JobStatus.pendingReview || requirement.status == JobStatus.active;
  if (!isLive) return const [];

  final messages = <String>[
    'You can edit this job and change salary. Typically it takes 3 to 5 days for caregivers '
        'to reach out. If urgent, do not hesitate to click on the red button at the top of '
        'the app for help.',
  ];

  final careReceiver = requirement.careReceiver;
  if (careReceiver != null) {
    final tier = deriveCareTier(careReceiver);
    final tierLabel = CareTier.displayNames[tier] ?? tier;
    messages.add(
      "Based on the patient's condition we see you need $tierLabel. You may look at the "
      'standard Rate Card for this care level. You can also tap Scope of Work on the job '
      'listing to see exactly what it covers.',
    );
  }

  messages.addAll([
    'You can post one requirement at a time — once the existing requirement is closed, '
        'fulfilled, or cancelled, you can post another. Tip: you may cancel a requirement '
        'at any time.',
    'If you are not getting applicants, consider widening your scope: move to a monthly or '
        'long-term requirement, stay open to candidates of any religion, or set Preferred '
        'Caregiver Gender and Language Preference to "No Preference" — caregivers are '
        'trained to handle any gender, so this can significantly widen your pool of '
        'candidates.',
  ]);

  return messages;
}
