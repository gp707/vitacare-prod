import '../constants/enums.dart';
import 'care_receiver_model.dart';

/// The 3 care tiers a job can derive to — see [deriveCareTier] below for how
/// a job's care_receiver maps to one of these. Never manually picked by an
/// admin or individual; always computed from the care needs they already
/// selected while posting/editing.
class CareTier {
  static const companionCare = 'companion_care';
  static const bedsideCare = 'bedside_care';
  static const criticalCare = 'critical_care';

  static const all = [companionCare, bedsideCare, criticalCare];

  static const displayNames = {
    companionCare: 'Companion Care',
    bedsideCare: 'Bedside Care',
    criticalCare: 'Critical Care',
  };
}

/// Derives which [CareTier] a job's care needs fall into, purely from its
/// [CareReceiverModel.toiletAssistance] and [CareReceiverModel.feedingType]
/// — there is no separate "type of care" field for an admin or individual
/// to pick, and (as of this rule set) Medical Condition and Vital
/// Monitoring no longer factor in at all — those two fields are still
/// collected and shown, they just don't move the tier/suggested rate.
///
/// Checked highest-tier-first, matching the "Everything in X, plus…"
/// cumulative framing the 3 tiers are written with in the admin-editable
/// Scope of Work content. Toilet Assistance options are Independent,
/// Diapers/bedside support, Catheter support, Others; Feeding Type options
/// are Oral feeding, Tube feeding, Others (Cannula etc.):
///
/// - [CareTier.criticalCare]: Catheter support OR Others toileting, OR Tube
///   feeding OR Others feeding — any one of these alone is enough,
///   regardless of what's selected on the other axis.
/// - [CareTier.bedsideCare] (else): Diapers/bedside toileting support.
/// - [CareTier.companionCare]: the baseline case — Independent toileting +
///   Oral feeding, with nothing on either axis pushing higher.
///
/// This mapping is a product judgment call, not a value the backend
/// enforces — reviewable/adjustable here in one place if the intended
/// tiering changes.
String deriveCareTier(CareReceiverModel careReceiver) {
  final toiletAssistance = careReceiver.toiletAssistance;

  final isCritical = toiletAssistance.contains(ToiletAssistance.usesCatheter) ||
      toiletAssistance.contains(ToiletAssistance.others) ||
      careReceiver.feedingType == FeedingType.tubeFeeding ||
      careReceiver.feedingType == FeedingType.others;
  if (isCritical) return CareTier.criticalCare;

  final isBedside = toiletAssistance.contains(ToiletAssistance.diapersBedsideSupport);
  if (isBedside) return CareTier.bedsideCare;

  return CareTier.companionCare;
}
