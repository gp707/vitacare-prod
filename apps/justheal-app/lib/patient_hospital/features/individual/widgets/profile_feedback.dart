import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/providers.dart';
import 'feedback_widgets.dart';
import 'salary_actions.dart';

/// The patient/family's own feedback about a caregiver, shown on that caregiver's profile page (where
/// the patient writes or changes it). The caregiver's feedback about the patient is private and never
/// appears. [onSaved] lets the list behind the profile refresh.
class ProfileFeedback extends ConsumerStatefulWidget {
  final String jobId;
  final JobApplicationModel application;
  final VoidCallback? onSaved;

  const ProfileFeedback({super.key, required this.jobId, required this.application, this.onSaved});

  @override
  ConsumerState<ProfileFeedback> createState() => _ProfileFeedbackState();
}

class _ProfileFeedbackState extends ConsumerState<ProfileFeedback> {
  late JobApplicationModel _application = widget.application;

  bool get _eligible =>
      feedbackEligible(acceptedAt: _application.acceptedAt, agreedStartDate: _application.agreedStartDate);

  Future<void> _open() async {
    final saved = await leaveFeedbackFlow(context, ref, jobId: widget.jobId, application: _application);
    if (!saved || !mounted) return;
    widget.onSaved?.call();
    try {
      final all = await ref.read(individualRepositoryProvider).listApplications(widget.jobId);
      final fresh = all.where((a) => a.id == _application.id).firstOrNull;
      if (fresh != null && mounted) setState(() => _application = fresh);
    } catch (_) {
      // The feedback is saved; the profile just keeps showing the old state until reopened.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_application.myFeedback == null && !_eligible) {
      return const Text(
        'You can leave feedback once the work has started.',
        key: Key('feedback-not-yet'),
        style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
        textAlign: TextAlign.center,
      );
    }
    return FeedbackSection(
      aboutLabel: 'caregiver',
      mine: _application.myFeedback,
      received: null,
      eligible: _eligible,
      onLeave: _open,
      onEdit: _open,
    );
  }
}
