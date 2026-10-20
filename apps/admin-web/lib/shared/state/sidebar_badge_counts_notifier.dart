import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../features/dashboard/data/dashboard_repository.dart';

/// Powers the three sidebar "needs immediate attention" badges (Tickets /
/// Jobs / Caregivers) — loaded once, same lifecycle as sessionProvider (see
/// RootScreen.initState), and watched by AppShell, which wraps every
/// authenticated screen, so the counts stay visible everywhere in the
/// sidebar rather than only while on the Dashboard screen itself. Reuses
/// the same GET /admin/dashboard/stats the Dashboard screen's own
/// (separate, unshared) fetch already calls — cheap aggregate COUNT(*)
/// queries server-side, not a full paginated list fetch per badge.
///
/// A one-time load at app start (not a live/periodic refresh) deliberately
/// matches how DashboardStats itself is already treated elsewhere in this
/// app — see DashboardScreen's own single fetch-on-visit, never kept live.
class SidebarBadgeCountsNotifier extends StateNotifier<DashboardStats?> {
  final DashboardRepository _repository;

  SidebarBadgeCountsNotifier(this._repository) : super(null);

  Future<void> load() async {
    try {
      state = await _repository.getStats();
    } catch (_) {
      // Fail silently — a missing badge count isn't worth an error banner;
      // the sidebar just shows no badge until the next successful load.
    }
  }
}

final sidebarBadgeCountsProvider = StateNotifierProvider<SidebarBadgeCountsNotifier, DashboardStats?>((ref) {
  return SidebarBadgeCountsNotifier(ref.watch(dashboardRepositoryProvider));
});
