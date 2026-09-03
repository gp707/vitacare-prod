import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/rate_card_button.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/requirement_messages.dart';

/// Admin-editable, status-based tips about the patient/family's own posted
/// requirement(s) — see requirement_messages.dart's resolveMessages() for
/// exactly which messages apply and when. Message content/delivery-event
/// is admin-managed (apps/admin-web's "NurseNow Messages" screen); this
/// screen fetches the current template set + the individual's own
/// requirements (the same GET /individual/requirements call
/// JobsPostedScreen makes) in parallel, then — only when
/// needsApplicationsFetch() says there's actually something to check —
/// a 3rd call for the most recent requirement's own applications (the
/// caregiver_* events need to know who's applied/been accepted/rejected/
/// closed on it). Resolved entirely client-side — no persistence, no
/// read/unread state; refreshing always shows whatever currently applies,
/// nothing more.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<JobModel> _requirements = [];
  List<IndividualMessageModel> _templates = [];
  List<JobApplicationModel> _currentApplications = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final individualRepo = ref.read(individualRepositoryProvider);
      final results = await Future.wait([
        individualRepo.listMyRequirements(),
        ref.read(individualMessagesRepositoryProvider).get(),
      ]);
      final requirements = results[0] as List<JobModel>;
      final templates = results[1] as List<IndividualMessageModel>;
      final applications = needsApplicationsFetch(requirements)
          ? await individualRepo.listApplications(requirements.first.id)
          : <JobApplicationModel>[];
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _templates = templates;
        _currentApplications = applications;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = resolveMessages(_templates, _requirements, _currentApplications);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: const [RateCardButton(), WhatsAppHelpButton()],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: messages.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'No messages right now.',
                                  style:
                                      TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: messages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) => Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.06),
                                border: Border.all(color: AppColors.error, width: 2.5),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.sm),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(messages[index].icon,
                                        color: AppColors.primaryDark, size: 15),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(messages[index].text,
                                        style: const TextStyle(
                                            color: AppColors.success, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
      ),
      bottomNavigationBar: const NurseNowBottomNav(currentIndex: 1),
    );
  }
}
