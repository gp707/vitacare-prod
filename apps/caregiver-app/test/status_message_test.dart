import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/features/profile/status_message.dart';

void main() {
  group('statusMessageFor', () {
    test('gives distinct, accurate copy per status — not a single generic message', () {
      final messages = {
        for (final status in VerificationStatus.all) status: statusMessageFor(status, null),
      };

      expect(messages[VerificationStatus.pendingCall], contains('under review'));
      expect(messages[VerificationStatus.available], contains('verified'));
      expect(messages[VerificationStatus.available], isNot(contains('under review')));
      expect(messages[VerificationStatus.unavailable], contains('verified'));
      expect(messages[VerificationStatus.assigned], contains('assigned'));
      expect(messages[VerificationStatus.rejected], contains('not approved'));
    });

    test('includes the rejection reason when one is set', () {
      final message = statusMessageFor(VerificationStatus.rejected, 'Aadhaar document unreadable');
      expect(message, contains('Aadhaar document unreadable'));
    });

    test('falls back to a generic reason prompt when rejected with no message', () {
      final message = statusMessageFor(VerificationStatus.rejected, null);
      expect(message, contains('Contact the office'));
    });
  });
}
