/// Salary is paid every 2 weeks. From the day the caregiver starts, the first
/// payment falls due 14 days later, then every 14 days after that. The amount for
/// one period follows the agreed rate:
///   * per day:   rate x 14
///   * per month: rate x 14 / 30 (a fixed 30-day month, so the figure is the same
///                every cycle and easy to explain to both sides)
///
/// Leave days and pauses (set by the patient) reduce the days worked in the
/// period, and the pay with them: a per-day rate is paid for the days worked, a
/// per-month rate for `worked ÷ 30` of the month.
///
/// Pure Dart, no Flutter: used identically by the caregiver and patient apps, so
/// both sides always see the same date and amount.
const int salaryPeriodDays = 14;
const int salaryMonthDays = 30;

/// A stretch of paused salary: every day from [from] until [to] (exclusive — the
/// day it was resumed is a working day) counts as leave. [to] is null while the
/// salary is still paused. Dates are the API's YYYY-MM-DD.
class PausePeriod {
  final String from;
  final String? to;
  const PausePeriod({required this.from, this.to});

  factory PausePeriod.fromJson(Map<String, dynamic> json) =>
      PausePeriod(from: json['from'] as String, to: json['to'] as String?);

  bool get isOpen => to == null;

  /// Whether [day] (YYYY-MM-DD) falls in this pause.
  bool covers(String day) => day.compareTo(from) >= 0 && (to == null || day.compareTo(to!) < 0);
}

/// Parses the API's `leave_dates` (a list of YYYY-MM-DD) tolerantly.
List<String> parseLeaveDates(Object? json) =>
    json is List ? (json.map((e) => e.toString()).toList()..sort()) : const <String>[];

/// Parses the API's `pauses` (a list of {from, to}) tolerantly.
List<PausePeriod> parsePauses(Object? json) => json is List
    ? json.map((e) => PausePeriod.fromJson(e as Map<String, dynamic>)).toList()
    : const <PausePeriod>[];

/// YYYY-MM-DD for a date.
String toIsoDate(DateTime d) => _iso(d);

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Every date from [first] to [last] inclusive as YYYY-MM-DD (empty if [last] is
/// before [first]). Used to turn a picked date range into the days to mark as leave.
List<String> isoDatesBetween(DateTime first, DateTime last) {
  final start = DateTime.utc(first.year, first.month, first.day);
  final end = DateTime.utc(last.year, last.month, last.day);
  final days = <String>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    days.add(_iso(d));
  }
  return days;
}

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
  /// Days in this period that earn nothing: marked leave plus paused days
  /// (sorted, each once).
  final List<DateTime> leaveDays;
  /// Days actually worked in the period: 14 minus [leaveDays].
  final int workedDays;
  /// True while salary is paused (a pause with no end yet).
  final bool isPaused;
  /// The first day of the open pause, when [isPaused].
  final DateTime? pausedFrom;

  const SalaryDue({
    required this.dueDate,
    required this.daysLeft,
    required this.amount,
    required this.rate,
    required this.unit,
    required this.periodStart,
    this.leaveDays = const [],
    this.workedDays = salaryPeriodDays,
    this.isPaused = false,
    this.pausedFrom,
  });

  bool get isDueToday => daysLeft == 0;
}

/// Rupees owed for [days] worked days (default: a full 14-day period).
int salaryForPeriod({required int rate, required String unit, int days = salaryPeriodDays}) =>
    unit == 'daily' ? rate * days : (rate * days / salaryMonthDays).round();

/// The next salary due on or after [today] (default: now), or null when the
/// agreement is incomplete or the start date can't be read. [startDate] is the
/// API's YYYY-MM-DD.
SalaryDue? nextSalaryDue({
  required int? salary,
  required String? unit,
  required String? startDate,
  DateTime? today,
  List<String> leaveDates = const [],
  List<PausePeriod> pauses = const [],
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
  final periodStart = due.subtract(const Duration(days: salaryPeriodDays));

  // Leave days (marked, or inside a pause) in this period earn nothing.
  final marked = leaveDates.toSet();
  final leaveDays = <DateTime>[];
  for (var i = 0; i < salaryPeriodDays; i++) {
    final day = periodStart.add(Duration(days: i));
    final iso = _iso(day);
    if (marked.contains(iso) || pauses.any((p) => p.covers(iso))) leaveDays.add(day);
  }
  final worked = salaryPeriodDays - leaveDays.length;
  final openPause = pauses.where((p) => p.isOpen).toList();
  final pausedFrom = openPause.isEmpty ? null : DateTime.tryParse(openPause.first.from);
  return SalaryDue(
    dueDate: due,
    daysLeft: due.difference(todayDay).inDays,
    amount: salaryForPeriod(rate: salary, unit: unit!, days: worked),
    rate: salary,
    unit: unit,
    periodStart: periodStart,
    leaveDays: leaveDays,
    workedDays: worked,
    isPaused: openPause.isNotEmpty,
    pausedFrom: pausedFrom == null ? null : DateTime.utc(pausedFrom.year, pausedFrom.month, pausedFrom.day),
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

/// "Tue 25 Nov" — a short day label for leave chips (YYYY-MM-DD in).
String formatDayMonth(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return '${_weekdays[DateTime.utc(parsed.year, parsed.month, parsed.day).weekday - 1]} ${parsed.day} ${_months[parsed.month - 1]}';
}

/// "18 Nov 2026" (no weekday). Accepts the API's YYYY-MM-DD; returns the input
/// unchanged when it can't be read.
String formatLongDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
}

/// "today", "tomorrow" or "in 12 days".
String dueInWords(int daysLeft) =>
    daysLeft <= 0 ? 'today' : (daysLeft == 1 ? 'tomorrow' : 'in $daysLeft days');
