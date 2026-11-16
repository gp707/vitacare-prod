import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'package:nursenow_app/analytics/analytics.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';
import 'agreement_dialog.dart';
import 'leave_days_dialog.dart';

/// The actions a patient can take on one caregiver's salary: the agreed salary and
/// cycle start date, leave days and marking cycles paid. Used by the main screen (the popup
/// right after accepting) and by the caregiver's own salary page. Each returns true
/// when it changed something, so the caller knows to reload.

IndividualRepository _repo(WidgetRef ref) => ref.read(individualRepositoryProvider);

/// The popup to confirm / edit the agreed salary and start date.
Future<bool> openAgreementFlow(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required JobModel requirement,
  required JobApplicationModel application,
}) async {
  Analytics.tap('individual', 'requirement_posted', 'agreement_open');
  final saved = await showAgreementDialog(
    context,
    caregiverName: application.fullName,
    defaultUnit: requirement.frequencyOfCare == FrequencyOfCare.daily ? 'daily' : 'monthly',
    initialSalary: application.agreedSalary,
    initialSalaryUnit: application.agreedSalaryUnit,
    initialStartDate: application.agreedStartDate,
    onSubmit: (salary, salaryUnit, startDate) =>
        _repo(ref).setAgreement(jobId, application.id, salary: salary, salaryUnit: salaryUnit, startDate: startDate),
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to ${application.fullName}.')));
  }
  return saved;
}

/// Runs one leave call; a server error is shown as a banner.
Future<bool> _run(BuildContext context, Future<void> Function() action, String successMessage) async {
  try {
    await action();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showVitaErrorBanner(context, e.message);
    return false;
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String confirmLabel, {
  String cancelLabel = 'Not now',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(cancelLabel)),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Pick the specific days the caregiver is on leave (any days of the current cycle).
Future<bool> markLeaveFlow(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required JobApplicationModel application,
}) async {
  Analytics.tap('individual', 'requirement_posted', 'mark_leave');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Leave can only be marked inside the current salary cycle.
  final cycle = currentSalaryCycleRange(application.agreedStartDate, today: today);
  final firstDate = cycle?.start ?? today;
  final lastDate = cycle?.end ?? today;
  final dates = await showLeaveDaysDialog(
    context,
    firstDate: firstDate,
    lastDate: lastDate,
    // Open on the month of today, or of the cycle when today is outside it (a start date in the future).
    initialMonth: (today.isBefore(firstDate) || today.isAfter(lastDate)) ? firstDate : today,
    alreadyMarked: application.leaveDates,
    note: 'Leave can be marked only in the current salary cycle: '
        '${formatLongDate(toIsoDate(firstDate))} to ${formatLongDate(toIsoDate(lastDate))}.',
  );
  if (dates == null || dates.isEmpty || !context.mounted) return false;
  return _run(
    context,
    () => _repo(ref).markLeaves(jobId, application.id, dates),
    dates.length == 1
        ? 'Leave marked for ${formatDayMonth(dates.first)}. ${application.fullName} has been told.'
        : '${dates.length} leave days marked. ${application.fullName} has been told.',
  );
}

/// Cancels one marked day: it is a working day again.
Future<bool> cancelLeaveFlow(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required JobApplicationModel application,
  required String date,
}) async {
  final ok = await _confirm(
    context,
    'Cancel leave on ${formatDayMonth(date)}?',
    'It becomes a working day again and is paid. ${application.fullName} will be told.',
    'Cancel leave',
    cancelLabel: 'Keep leave',
  );
  if (!ok || !context.mounted) return false;
  Analytics.tap('individual', 'requirement_posted', 'cancel_leave');
  return _run(
    context,
    () => _repo(ref).cancelLeave(jobId, application.id, date),
    'Leave on ${formatDayMonth(date)} cancelled.',
  );
}

/// Marks one ended cycle as paid. The date picker doubles as the confirmation: it
/// starts on today, can go back to the first day of the cycle, never forward.
Future<bool> markCyclePaidFlow(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required JobApplicationModel application,
  required SalaryCycleModel cycle,
}) async {
  Analytics.tap('individual', 'requirement_posted', 'mark_cycle_paid');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime.tryParse(cycle.cycleStart) ?? today;
  final first = DateTime(start.year, start.month, start.day);
  final picked = await showDatePicker(
    context: context,
    initialDate: today,
    firstDate: first.isAfter(today) ? today : first,
    lastDate: today,
    helpText: 'Date \u20b9${formatRupees(cycle.amount)} was paid',
    confirmText: 'Mark as paid',
  );
  if (picked == null || !context.mounted) return false;
  return _run(
    context,
    () => _repo(ref).markSalaryCyclePaid(jobId, application.id, cycle.cycleStart, toIsoDate(picked)),
    'Marked as paid. ${application.fullName} will be told.',
  );
}
