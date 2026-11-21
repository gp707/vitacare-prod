import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

void main() {
  group('formatting', () {
    test('Indian digit grouping', () {
      expect(formatRupees(0), '0');
      expect(formatRupees(900), '900');
      expect(formatRupees(14000), '14,000');
      expect(formatRupees(140000), '1,40,000');
      expect(formatRupees(1400000), '14,00,000');
      expect(formatRupees(-14000), '-14,000');
    });

    test('long date without weekday, and a fallback for unreadable text', () {
      expect(formatLongDate('2026-11-18'), '18 Nov 2026');
      expect(formatLongDate('2027-01-05'), '5 Jan 2027');
      expect(formatLongDate('soon'), 'soon');
    });

    test('ISO date, zero-padded, whatever the time of day', () {
      expect(toIsoDate(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(toIsoDate(DateTime(2026, 11, 18)), '2026-11-18');
    });
  });
}
