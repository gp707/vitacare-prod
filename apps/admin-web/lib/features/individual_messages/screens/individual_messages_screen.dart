import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';

/// Maps an admin-picked MessageIcon key to real IconData for the row
/// preview/dropdown — Flutter-specific, so it can't live in the pure-Dart
/// packages/vitacare_shared package (same reasoning as nursenow-app's own
/// iconFor() in requirement_messages.dart, which this mirrors).
IconData _iconFor(String key) {
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
    case MessageIcon.info:
    default:
      return Icons.info;
  }
}

/// Admin CRUD for NurseNow Individual's "Messages" tab content — each row
/// is a message tied to one of 3 delivery events (MessageEvent), shown to
/// the individual client-side (resolveMessages() in nursenow-app) with no
/// extra network calls beyond the one GET this screen's own data backs.
/// Unlike Rate Card/Scope of Work/Duty Requirements (small singleton
/// config blobs folded into the Settings tab strip), this is genuine
/// multi-row record management — create/edit/delete any number of
/// messages — so it gets its own sidebar route, same shape as other
/// list-management screens.
class IndividualMessagesScreen extends ConsumerStatefulWidget {
  const IndividualMessagesScreen({super.key});

  @override
  ConsumerState<IndividualMessagesScreen> createState() => _IndividualMessagesScreenState();
}

class _IndividualMessagesScreenState extends ConsumerState<IndividualMessagesScreen> {
  List<IndividualMessageModel> _messages = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final messages = await ref.read(individualMessagesRepositoryProvider).list();
      messages.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      if (mounted) setState(() => _messages = messages);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _nextSuggestedOrder =>
      _messages.isEmpty ? 10 : (_messages.map((m) => m.displayOrder).reduce((a, b) => a > b ? a : b) + 10);

  Future<void> _showMessageDialog({IndividualMessageModel? existing}) async {
    String event = existing?.event ?? MessageEvent.requirementLive;
    String icon = existing?.icon ?? MessageIcon.info;
    bool enabled = existing?.enabled ?? true;
    final messageController = TextEditingController(text: existing?.message ?? '');
    final orderController =
        TextEditingController(text: (existing?.displayOrder ?? _nextSuggestedOrder).toString());
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Message' : 'Edit Message'),
          content: SizedBox(
            width: context.dialogWidth(480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: event,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Event'),
                    items: [
                      for (final e in MessageEvent.all)
                        DropdownMenuItem(
                          value: e,
                          child: Text(MessageEvent.displayNames[e] ?? e, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => event = value!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: icon,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Icon'),
                    items: [
                      for (final i in MessageIcon.all)
                        DropdownMenuItem(
                          value: i,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_iconFor(i), size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Text(i),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => icon = value!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      helperText: 'Use {tier} to insert the derived care tier (Companion/Bedside/Critical '
                          'Care) — only for the "care tier" event. Use {caregiver_name} to insert the '
                          'applicant\'s name — only for the 4 caregiver applied/accepted/rejected/closed '
                          'events, which fire once per matching applicant.',
                      helperMaxLines: 4,
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: orderController,
                    decoration: const InputDecoration(
                      labelText: 'Display order',
                      helperText: 'Lower numbers show first — messages from every applicable '
                          'event are sorted together by this value.',
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(dialogError!, style: const TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final message = messageController.text.trim();
                final order = int.tryParse(orderController.text.trim());
                if (message.isEmpty || order == null) {
                  setDialogState(() => dialogError = 'Message and a numeric display order are required.');
                  return;
                }
                final model = IndividualMessageModel(
                  id: existing?.id ?? '',
                  event: event,
                  icon: icon,
                  message: message,
                  displayOrder: order,
                  enabled: enabled,
                );
                try {
                  final repo = ref.read(individualMessagesRepositoryProvider);
                  if (existing == null) {
                    await repo.create(model);
                  } else {
                    await repo.update(existing.id, model);
                  }
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ApiException catch (e) {
                  setDialogState(() => dialogError = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) await _load();
  }

  Future<void> _confirmDelete(IndividualMessageModel message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this message?'),
        content: Text(message.message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(individualMessagesRepositoryProvider).delete(message.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.nursenowMessages,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NurseNow Messages',
                      style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: () => _showMessageDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Message'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Tips shown on NurseNow Individual\'s Messages tab. Each message fires on one '
                'event; messages are shown together sorted by Display Order.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else
                Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      itemCount: _messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final message = _messages[index];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            color: message.enabled ? null : AppColors.background,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFor(message.icon), color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(MessageEvent.displayNames[message.event] ?? message.event,
                              style: const TextStyle(fontSize: AppTypography.small)),
                        ),
                        Text('Order: ${message.displayOrder}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
                        if (!message.enabled)
                          const Text('Disabled',
                              style: TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(message.message),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _showMessageDialog(existing: message),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () => _confirmDelete(message),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }
}
