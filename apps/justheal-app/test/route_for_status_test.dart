import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/app/route_for_status.dart';
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart';

SessionAuthenticated _session(String status) => SessionAuthenticated(
      fullName: 'Nurse One',
      phone: '+919876543210',
      verificationStatus: status,
      hasRequiredDocuments: true,
    );

void main() {
  group('routeForStatus', () {
    test('pendingCall goes to the waiting screen', () {
      expect(routeForStatus(_session(VerificationStatus.pendingCall)), '/caregiver/pending-call');
    });

    test('assigned goes to MyJobs', () {
      expect(routeForStatus(_session(VerificationStatus.assigned)), '/caregiver/my-jobs');
    });

    test('rejected goes to Jobs (browsing doubles as a nudge to fix/resubmit)', () {
      expect(routeForStatus(_session(VerificationStatus.rejected)), '/caregiver/jobs');
    });

    test('available/unavailable go to Profile View', () {
      expect(routeForStatus(_session(VerificationStatus.available)), '/caregiver/profile');
      expect(routeForStatus(_session(VerificationStatus.unavailable)), '/caregiver/profile');
    });
  });

  group('routeArgumentsForStatus', () {
    // The actual feature request: a caregiver who is `assigned` (selected
    // for a job) lands on MyJobs's Selected tab specifically, not just the
    // MyJobs screen defaulting to Applied.
    test('assigned carries MyAssignmentScreenArgs pointing at the Selected tab (index 1)', () {
      final args = routeArgumentsForStatus(_session(VerificationStatus.assigned));
      expect(args, isA<MyAssignmentScreenArgs>());
      expect((args as MyAssignmentScreenArgs).initialTabIndex, 1);
    });

    test('every other status carries no arguments', () {
      for (final status in [
        VerificationStatus.pendingCall,
        VerificationStatus.rejected,
        VerificationStatus.available,
        VerificationStatus.unavailable,
      ]) {
        expect(routeArgumentsForStatus(_session(status)), isNull, reason: 'status=$status');
      }
    });
  });

  group('MyAssignmentScreenArgs', () {
    test('defaults to the Applied tab (index 0) when constructed with no argument', () {
      expect(const MyAssignmentScreenArgs().initialTabIndex, 0);
    });
  });
}
