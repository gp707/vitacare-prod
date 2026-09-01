import '../constants/enums.dart';

/// Mirrors the `GET /duty-requirements` / `GET /admin/duty-requirements`
/// response — a single admin-editable set of 3 independent bullet lists,
/// one per [DutyType] shift, describing what the patient/family must
/// arrange for the nurse under that shift (bedding/meals/supplies, no
/// cooking or household chores, etc.). Unlike [ScopeOfWorkModel]'s tiers,
/// these lists are NOT cumulative — each shift stands alone, matched
/// exactly to whichever one is currently selected on the form, never
/// stacked with another.
class DutyRequirementsModel {
  final List<String> liveIn;
  final List<String> dayDuty;
  final List<String> nightDuty;

  const DutyRequirementsModel({
    required this.liveIn,
    required this.dayDuty,
    required this.nightDuty,
  });

  factory DutyRequirementsModel.fromJson(Map<String, dynamic> json) => DutyRequirementsModel(
        liveIn: List<String>.from(json['live_in'] as List),
        dayDuty: List<String>.from(json['day_duty'] as List),
        nightDuty: List<String>.from(json['night_duty'] as List),
      );

  Map<String, dynamic> toJson() => {
        'live_in': liveIn,
        'day_duty': dayDuty,
        'night_duty': nightDuty,
      };

  /// Bullets for [dutyType] — no stacking, just that one shift's own list.
  List<String> bulletsFor(String dutyType) {
    switch (dutyType) {
      case DutyType.dayDuty:
        return dayDuty;
      case DutyType.nightDuty:
        return nightDuty;
      case DutyType.liveIn:
      default:
        return liveIn;
    }
  }
}
