import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/push/push_handler.dart';

void main() {
  group('routeFromPushData', () {
    test('follows the caregiver screens a push is allowed to open', () {
      expect(
          routeFromPushData({'route': '/caregiver/jobs'}), '/caregiver/jobs');
      expect(routeFromPushData({'route': '/caregiver/my-jobs'}),
          '/caregiver/my-jobs');
      expect(routeFromPushData({'route': '/caregiver/profile'}),
          '/caregiver/profile');
    });

    test('ignores a missing, non-string or unknown route', () {
      expect(routeFromPushData({}), isNull);
      expect(routeFromPushData({'route': 42}), isNull);
      expect(routeFromPushData({'route': '/login'}), isNull);
      expect(
          routeFromPushData({'route': '/caregiver/jobs/../../admin'}), isNull);
    });
  });
}
