import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the permanent left sidebar is collapsed to its icon rail. Kept in
/// a provider (not widget state) because every screen builds its own
/// AppShell — local state would reset on each navigation. Remembered across
/// reloads; a missing or unreadable preference just means "expanded".
class SidebarCollapsedNotifier extends StateNotifier<bool> {
  static const _prefsKey = 'sidebar_collapsed';

  SidebarCollapsedNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, state);
    } catch (_) {}
  }
}

final sidebarCollapsedProvider =
    StateNotifierProvider<SidebarCollapsedNotifier, bool>((ref) => SidebarCollapsedNotifier());
