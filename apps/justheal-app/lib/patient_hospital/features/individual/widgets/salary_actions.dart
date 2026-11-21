import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:nursenow_app/analytics/analytics.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';
import 'agreement_dialog.dart';
import 'package:nursenow_app/share/share_messages.dart';
import 'package:nursenow_app/share/share_service.dart';
import 'feedback_widgets.dart';

/// The actions a patient can take on one accepted caregiver: enter or change the agreed
/// salary and start date (one popup with both fields), and leave or change feedback. Each
/// returns true when it changed something, so the caller knows to reload.

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

/// Rate this caregiver (stars + a short comment), once the work has started — or change the
/// feedback already left ([application] has `myFeedback`): the sheet opens filled in and Save
/// replaces it. Returns true when it was saved (the caller reloads).
Future<bool> leaveFeedbackFlow(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required JobApplicationModel application,
}) async {
  final existing = application.myFeedback;
  Analytics.tap('individual', 'requirement_posted', existing == null ? 'leave_feedback' : 'edit_feedback');
  final saved = await showFeedbackSheet(
    context,
    title: existing == null ? 'Rate ${application.fullName}' : 'Your feedback for ${application.fullName}',
    existing: existing,
    canChangeLater: true,
    onSubmit: (rating, comment) => existing == null
        ? _repo(ref).submitFeedback(jobId, application.id, rating, comment)
        : _repo(ref).updateFeedback(jobId, application.id, rating, comment),
  );
  if (saved && context.mounted) {
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your feedback was updated.')));
    } else {
      // A good moment to ask: one tap on the snackbar opens WhatsApp with the invite typed.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Thank you for your feedback.'),
        action: SnackBarAction(
          label: 'Share JustHeal',
          onPressed: () => shareViaWhatsApp(context, ref, appInviteMessage(ShareAudience.individual),
              flow: 'individual', screen: 'requirement_posted', action: 'share_app_after_feedback'),
        ),
      ));
    }
  }
  return saved;
}
