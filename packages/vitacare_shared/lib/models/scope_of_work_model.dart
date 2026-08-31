import 'care_tier.dart';

/// Mirrors the `GET /scope-of-work` / `GET /admin/scope-of-work` response —
/// a single admin-editable set of 3 cumulative bullet lists (Companion Care
/// / Bedside Care / Critical Care), shown to caregivers (NurseJobs) via a
/// per-job "Scope of Work" popup. Which tier applies to a given job is
/// DERIVED from that job's care_receiver fields (see [deriveCareTier] in
/// care_tier.dart) — never manually picked, and never shown on Organisation
/// postings, which have no care_receiver to derive a tier from.
/// [bedsideCare] and [criticalCare] are each meant to be read cumulatively
/// with the tier(s) below them ("Everything in Companion Care, plus…") —
/// that stacking is done by the caller when rendering, not stored here.
class ScopeOfWorkModel {
  final List<String> companionCare;
  final List<String> bedsideCare;
  final List<String> criticalCare;

  const ScopeOfWorkModel({
    required this.companionCare,
    required this.bedsideCare,
    required this.criticalCare,
  });

  factory ScopeOfWorkModel.fromJson(Map<String, dynamic> json) => ScopeOfWorkModel(
        companionCare: List<String>.from(json['companion_care'] as List),
        bedsideCare: List<String>.from(json['bedside_care'] as List),
        criticalCare: List<String>.from(json['critical_care'] as List),
      );

  Map<String, dynamic> toJson() => {
        'companion_care': companionCare,
        'bedside_care': bedsideCare,
        'critical_care': criticalCare,
      };

  /// Bullets for [tier], stacked cumulatively with every tier below it —
  /// e.g. for [CareTier.criticalCare] this returns companionCare +
  /// bedsideCare + criticalCare, matching the "Everything in X, plus…"
  /// framing the tiers are written with.
  List<String> bulletsFor(String tier) {
    switch (tier) {
      case CareTier.bedsideCare:
        return [...companionCare, ...bedsideCare];
      case CareTier.criticalCare:
        return [...companionCare, ...bedsideCare, ...criticalCare];
      case CareTier.companionCare:
      default:
        return [...companionCare];
    }
  }
}
