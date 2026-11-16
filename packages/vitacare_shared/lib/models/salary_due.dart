/// Salary is paid every 2 weeks. From the day the caregiver starts, the first
/// payment falls due 14 days later, then every 14 days after that. The amount for
/// one period follows the agreed rate:
///   * per day:   rate x 14
///   * per month: rate x 14 / 30 (a fixed 30-day month, so the figure is the same
///                every cycle and easy to explain to both sides)
///
/// Pure Dart, no Flutter: used identically by the caregiver and patient apps, so
/// both sides always see the same date and amount.
const int salaryPeriodDays = 14;
const int salaryMonthDays = 30;

class SalaryDue {
  /// The date the next payment is due (date only, UTC midnight).
  final DateTime dueDate;
  /// Whole days from today until [dueDate]; 0 means due today.
  final int daysLeft;
  /// Rupees for one 14-day period at the agreed rate.
  final int amount;
  /// The agreed rate as entered: rupees per day or per month.
  final int rate;
  /// 'daily' or 'monthly'.
  final String unit;
  /// The first day of the 14-day period this payment covers.
  final DateTime periodStart;

  const SalaryDue({
    required this.dueDate,
    required this.daysLeft,
    required this.amount,
    required this.rate,
    required this.unit,
    required this.periodStart,
  });

  bool get isDueToday => daysLeft == 0;
}

/// Rupees owed for one 14-day period.
int salaryForPeriod({required int rate, required String unit}) =>
    unit == 'daily' ? rate * salaryPeriodDays : (rate * salaryPeriodDays / salaryMonthDays).round();

/// The next salary due on or after [today] (default: now), or null when the
/// agreement is incomplete or the start date can't be read. [startDate] is the
/// API's YYYY-MM-DD.
SalaryDue? nextSalaryDue({
  required int? salary,
  required String? unit,
  required String? startDate,
  DateTime? today,
}) {
  if (salary == null || salary <= 0 || startDate == null || (unit != 'daily' && unit != 'monthly')) return null;
  final start = DateTime.tryParse(startDate);
  if (start == null) return null;
  final startDay = DateTime.utc(start.year, start.month, start.day);
  final now = today ?? DateTime.now();
  final todayDay = DateTime.utc(now.year, now.month, now.day);

  // First payment is 14 days after the start; then every 14 days.
  var periods = 1;
  final elapsed = todayDay.difference(startDay).inDays;
  if (elapsed > salaryPeriodDays) {
    periods = (elapsed / salaryPeriodDays).ceil();
  }
  final due = startDay.add(Duration(days: salaryPeriodDays * periods));
  return SalaryDue(
    dueDate: due,
    daysLeft: due.difference(todayDay).inDays,
    amount: salaryForPeriod(rate: salary, unit: unit!),
    rate: salary,
    unit: unit,
    periodStart: due.subtract(const Duration(days: salaryPeriodDays)),
  );
}

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

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Fri 4 Dec 2026".
String formatDueDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';

/// "today", "tomorrow" or "in 12 days".
String dueInWords(int daysLeft) =>
    daysLeft <= 0 ? 'today' : (daysLeft == 1 ? 'tomorrow' : 'in $daysLeft days');
