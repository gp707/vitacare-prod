import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One recipient selected for a bulk push notification — role-tagged so
/// the compose dialog/cart bar can show a breakdown ("3 caregivers, 2
/// patients, 1 organisation") rather than a bare count.
class SelectedRecipient {
  final String userId;
  final String role; // 'caregiver' | 'individual' | 'organisation'
  final String displayName;

  const SelectedRecipient({
    required this.userId,
    required this.role,
    required this.displayName,
  });
}

/// Persists across navigation between the Caregivers/Patients-Family/
/// Rehab-Hospitals list screens (it's a plain Riverpod provider, not tied
/// to any one screen's widget tree) — admin builds up a mixed-role
/// selection via each screen's own existing search/filter, then composes
/// one push notification targeting everyone selected so far, from
/// whichever of those screens they're currently on.
class RecipientSelectionCartNotifier extends StateNotifier<Map<String, SelectedRecipient>> {
  RecipientSelectionCartNotifier() : super(const {});

  bool contains(String userId) => state.containsKey(userId);

  void toggle(SelectedRecipient recipient) {
    final next = Map<String, SelectedRecipient>.from(state);
    if (next.containsKey(recipient.userId)) {
      next.remove(recipient.userId);
    } else {
      next[recipient.userId] = recipient;
    }
    state = next;
  }

  /// Used by "select all on this page" — never removes anything, so
  /// toggling it on a page that's a mix of already-selected and
  /// not-yet-selected rows is additive, not a reset.
  void addAll(Iterable<SelectedRecipient> recipients) {
    final next = Map<String, SelectedRecipient>.from(state);
    for (final recipient in recipients) {
      next[recipient.userId] = recipient;
    }
    state = next;
  }

  void removeAll(Iterable<String> userIds) {
    final next = Map<String, SelectedRecipient>.from(state);
    for (final userId in userIds) {
      next.remove(userId);
    }
    state = next;
  }

  void clear() => state = const {};
}

final recipientSelectionCartProvider =
    StateNotifierProvider<RecipientSelectionCartNotifier, Map<String, SelectedRecipient>>(
  (ref) => RecipientSelectionCartNotifier(),
);
