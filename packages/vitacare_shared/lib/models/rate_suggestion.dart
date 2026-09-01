import '../constants/enums.dart';
import 'care_tier.dart';
import 'rate_card_model.dart';

/// Which Rate Card frequency table backs a given [CareDuration] selection —
/// a short engagement (few days/weeks) is priced off the daily grid, a
/// longer one (few months/long term) off the monthly grid. Used by
/// nursenow-app's Nurse Fee Guidance section to derive Frequency of Care
/// automatically from the patient's own Duration Care is Needed choice,
/// rather than admin picking it manually.
String frequencyForCareDuration(String careDuration) {
  switch (careDuration) {
    case CareDuration.fewDays:
    case CareDuration.fewWeeks:
      return FrequencyOfCare.daily;
    case CareDuration.fewMonths:
    case CareDuration.longTerm:
    default:
      return FrequencyOfCare.monthly;
  }
}

/// Looks up the admin-set suggested rate for a given [careTier] from
/// whichever [rateCards] entry matches [frequencyOfCare] — the free-text
/// cell from the Rate Card's single "Care" row, in the column matching the
/// tier (Companion/Bedside/Critical, same order as [CareTier.all]). Returns
/// null if the matching frequency row isn't present in [rateCards] (e.g. a
/// failed fetch) or is malformed (wrong cell count) — callers should fall
/// back to leaving the salary field for manual entry in that case, never
/// throw.
String? suggestedRate(List<RateCardModel> rateCards, String careTier, String frequencyOfCare) {
  final columnIndex = CareTier.all.indexOf(careTier);
  if (columnIndex == -1) return null;

  for (final rateCard in rateCards) {
    if (rateCard.frequencyOfCare != frequencyOfCare) continue;
    if (rateCard.cells.isEmpty) return null;
    final row = rateCard.cells[0];
    if (columnIndex >= row.length) return null;
    return row[columnIndex];
  }
  return null;
}
