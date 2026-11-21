import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/caregiver/features/profile/status_message.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

void main() {
  group('the caregiver profile status message', () {
    test('an assigned caregiver is told the profile is active (not that they are assigned to a job)', () {
      expect(statusMessageFor(VerificationStatus.assigned, null), 'Your profile is active.');
      expect(statusMessageFor(VerificationStatus.assigned, null), isNot(contains('assigned to a job')));
    });

    test('a caregiver marked not taking work is told the profile is inactive', () {
      expect(statusMessageFor(VerificationStatus.unavailable, null), 'Your profile is inactive.');
    });

    test('a caregiver waiting for verification still sees the under-review message', () {
      expect(statusMessageFor(VerificationStatus.pendingCall, null), "Your profile is under review. We'll notify you once verified.");
    });

    test('available and rejected keep their own messages', () {
      expect(statusMessageFor(VerificationStatus.available, null), startsWith("You're verified and available."));
      expect(statusMessageFor(VerificationStatus.rejected, null), 'Your application was not approved. Contact the office for details.');
      expect(statusMessageFor(VerificationStatus.rejected, 'Blurry selfie'), 'Your application was not approved: Blurry selfie');
    });
  });
}
