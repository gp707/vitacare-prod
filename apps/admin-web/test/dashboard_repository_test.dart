import 'package:flutter_test/flutter_test.dart';

import 'package:admin_web/features/dashboard/data/dashboard_repository.dart';

Map<String, dynamic> _baseJson() => {
      'total_caregivers': 100,
      'pending_call': 10,
      'available': 60,
      'unavailable': 5,
      'assigned': 20,
      'rejected': 5,
      'pending_edits_count': 3,
      'new_registrations_24h': 1,
      'new_registrations_7d': 8,
      'jobs_pending_approval': 4,
      'new_organisations_7d': 2,
      'new_individuals_7d': 6,
    };

void main() {
  group('DashboardStats.fromJson', () {
    test('parses open_tickets_count when the backend sends it', () {
      final json = _baseJson()..['open_tickets_count'] = 7;
      final stats = DashboardStats.fromJson(json);
      expect(stats.openTicketsCount, 7);
      expect(stats.jobsPendingApproval, 4);
      expect(stats.pendingCall, 10);
    });

    // Regression: a backend deploy still running the pre-open_tickets_count
    // version of GET /admin/dashboard/stats simply omits the key — this
    // must not throw, or every other field (and the whole Dashboard
    // screen, and every sidebar badge) silently breaks along with it, since
    // a thrown TypeError here isn't an ApiException and propagates past
    // both DashboardRepository's and DashboardScreen's own error handling.
    test('defaults open_tickets_count to 0 (not a throw) when the key is missing from an older backend response',
        () {
      final json = _baseJson();
      expect(json.containsKey('open_tickets_count'), isFalse);

      final stats = DashboardStats.fromJson(json);

      expect(stats.openTicketsCount, 0);
      // Every other field still parses correctly — the whole dashboard
      // doesn't go blank just because this one newer field is absent.
      expect(stats.totalCaregivers, 100);
      expect(stats.jobsPendingApproval, 4);
      expect(stats.pendingCall, 10);
    });
  });
}
