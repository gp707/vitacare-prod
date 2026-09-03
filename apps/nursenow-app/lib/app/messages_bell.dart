import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/network/api_exception.dart';
import '../core/providers.dart';
import '../features/individual/data/requirement_messages.dart';
import 'rate_card_button.dart';
import 'whatsapp_help_button.dart';

/// Replaces the old dedicated Messages tab/screen: Rate Card + Help stay
/// paired but move to the middle of the AppBar, and this returns the full
/// trailing `actions` list — the pair centered in whatever space remains,
/// with the bell pinned flush right where the pair alone used to sit.
/// [showBell] is false only for a shared route (profile_screen.dart) when
/// the session turns out to be Organisation — Organisation has no
/// requirement/care-tier/applicant concepts feeding resolveMessages(), so
/// there's nothing for a bell on that account type to count.
List<Widget> individualAppBarActions({required bool showBell}) => [
      Expanded(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [RateCardButton(), WhatsAppHelpButton()],
          ),
        ),
      ),
      if (showBell) const MessagesBellButton(),
    ];

/// A swinging bell with an unread-count badge, replacing the old Messages
/// tab. Unlike RateCardButton (which fetches lazily on tap), this fetches
/// eagerly on mount — the badge count must be known before the user ever
/// taps it. Resolves the exact same admin-editable message set the old
/// MessagesScreen did (see requirement_messages.dart's resolveMessages()),
/// just rendered in a bottom-sheet overlay instead of its own page.
///
/// Read/unread is tracked on-device only (LocalStorage.readMessageIds/
/// markMessagesRead) — no backend read-state table, keeping this
/// feature's "no persistence, fetched fresh" architecture intact.
/// Opening the overlay does NOT mark anything read by itself — each row is
/// individually tappable, opening that one message in its own popup (see
/// _openMessageDetail). Only once the popup is closed does that message
/// get marked read (and the badge decremented) — so an unread message
/// stays unread until the user actually opens and dismisses it, not just
/// on a bare tap.
class MessagesBellButton extends ConsumerStatefulWidget {
  const MessagesBellButton({super.key});

  @override
  ConsumerState<MessagesBellButton> createState() => _MessagesBellButtonState();
}

class _MessagesBellButtonState extends ConsumerState<MessagesBellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _swing;

  List<MessageItem> _messages = const [];
  String? _error;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _swing = Tween<double>(begin: -0.12, end: 0.12).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      final messages = resolveMessages(templates, requirements, applications);
      final readIds = ref.read(localStorageProvider).readMessageIds;
      setState(() {
        _messages = messages;
        _error = null;
        _unreadCount = messages.where((m) => !readIds.contains(m.id)).length;
      });
      _syncAnimation();
    } on ApiException catch (e) {
      // Fails open — a passive badge must never crash or block the screen
      // it's embedded in over a failed fetch, same convention RateCardButton
      // already follows for its own dialog fetch.
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _syncAnimation() {
    if (_unreadCount > 0) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  /// Shows a single message's full content in its own popup — tapping a
  /// row in the overlay list opens this instead of marking it read
  /// immediately. [onClosed] (which actually marks the message read) only
  /// runs once the popup is dismissed, whether via the Close button or by
  /// tapping the barrier — showDialog's Future resolves on either path.
  Future<void> _openMessageDetail(BuildContext context, MessageItem message, {required VoidCallback onClosed}) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(message.icon, color: AppColors.primaryDark, size: 17),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message.text)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    onClosed();
  }

  void _openOverlay() {
    final messages = _messages;
    final error = _error;
    // Mutated in place as rows are tapped — a local snapshot (not re-read
    // from LocalStorage per rebuild) so the sheet's own StatefulBuilder can
    // synchronously reflect a tap without waiting on the write to land.
    final readIds = {...ref.read(localStorageProvider).readMessageIds};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> markRead(String id) async {
            if (readIds.contains(id)) return;
            setSheetState(() => readIds.add(id));
            await ref.read(localStorageProvider).markMessagesRead([id]);
            if (!mounted) return;
            setState(() => _unreadCount = messages.where((m) => !readIds.contains(m.id)).length);
            _syncAnimation();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text('Messages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.title)),
                      ),
                      if (error != null)
                        Text(error, style: const TextStyle(color: AppColors.error))
                      else if (messages.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Center(
                            child: Text('No messages right now.', style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: messages.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isRead = readIds.contains(message.id);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openMessageDetail(sheetContext, message, onClosed: () => markRead(message.id)),
                                borderRadius: BorderRadius.circular(AppSpacing.sm),
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: isRead
                                        ? AppColors.textSecondary.withValues(alpha: 0.05)
                                        : AppColors.success.withValues(alpha: 0.06),
                                    border: Border.all(
                                      color: isRead ? AppColors.textSecondary.withValues(alpha: 0.3) : AppColors.error,
                                      width: isRead ? 1 : 2.5,
                                    ),
                                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: isRead ? AppColors.textSecondary.withValues(alpha: 0.15) : AppColors.primaryLight,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(message.icon,
                                            color: isRead ? AppColors.textSecondary : AppColors.primaryDark, size: 15),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(message.text,
                                            style: TextStyle(
                                                color: isRead ? AppColors.textSecondary : AppColors.success,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Messages',
          onPressed: _openOverlay,
          icon: AnimatedBuilder(
            animation: _swing,
            builder: (context, child) => Transform.rotate(
              angle: _swing.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: const Icon(Icons.notifications),
          ),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '$_unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
