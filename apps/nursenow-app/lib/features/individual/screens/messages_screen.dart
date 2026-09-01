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

/// Automatically-generated, status-based tips about the patient/family's
/// own posted requirement(s), plus a first-time welcome/orientation
/// ([welcomeMessages]) before they've ever posted one — see
/// requirement_messages.dart for exactly which messages apply and when.
/// Purely a computed view over data already fetched via
/// GET /individual/requirements (the same call JobsPostedScreen makes) —
/// no new backend endpoint, no persistence, no read/unread state;
/// refreshing this screen always shows whatever currently applies, nothing
/// more.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<JobModel> _requirements = [];
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
      final requirements =
          await ref.read(individualRepositoryProvider).listMyRequirements();
      if (!mounted) return;
      setState(() => _requirements = requirements);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      ...welcomeMessages(_requirements),
      for (final requirement in _requirements)
        ...messagesForRequirement(requirement),
    ];

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
                                color: AppColors.surface,
                                border: Border.all(color: AppColors.border),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.sm),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: AppColors.primary, size: 20),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(child: Text(messages[index])),
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
