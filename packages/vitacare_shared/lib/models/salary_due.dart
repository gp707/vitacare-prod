/// Small formatting helpers for the agreed salary and start date (the patient/family
/// enters both in one popup after accepting a caregiver; the caregiver sees them).
/// Pure Dart, no Flutter: used identically by the caregiver and patient apps.
///
/// (The file keeps its old name; the salary-due, leave and salary-cycle logic that used
/// to live here was removed together with those features.)

/// YYYY-MM-DD for a date.
String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 14000 -> "14,000", 140000 -> "1,40,000" (Indian digit grouping).
String formatRupees(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  if (digits.length <= 3) return '${negative ? '-' : ''}$digits';
  final lastThree = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${negative ? '-' : ''}${groups.join(',')},$lastThree';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "18 Nov 2026" (no weekday). Accepts the API's YYYY-MM-DD; returns the input
/// unchanged when it can't be read.
String formatLongDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
}
