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

/// Derives which [CareTier] a job's care needs fall into, purely from the
/// fields already collected on its [CareReceiverModel] — there is no
/// separate "type of care" field for an admin or individual to pick.
///
/// Checked highest-tier-first, matching the "Everything in X, plus…"
/// cumulative framing the 3 tiers are written with in the admin-editable
/// Scope of Work content:
///
/// - [CareTier.criticalCare]: any need for catheter care, tube feeding,
///   vitals monitoring, insulin/injection support, oxygen support, or
///   cannula care.
/// - [CareTier.bedsideCare] (else): any need for diaper/bedpan/commode
///   assistance, feeding assistance, or any other medical condition.
/// - [CareTier.companionCare]: the baseline/independent case — everything
///   else.
///
/// This mapping is a product judgment call, not a value the backend
/// enforces — reviewable/adjustable here in one place if the intended
/// tiering changes.
String deriveCareTier(CareReceiverModel careReceiver) {
  final toiletAssistance = careReceiver.toiletAssistance;
  final medicalConditions = careReceiver.medicalConditions;

  final isCritical = toiletAssistance.contains(ToiletAssistance.usesCatheter) ||
      careReceiver.feedingType == FeedingType.tubeFeeding ||
      careReceiver.feedingType == FeedingType.oralAndTube ||
      careReceiver.requiresVitalMonitoring ||
      medicalConditions.contains(MedicalCondition.insulinAdministrationSupport) ||
      medicalConditions.contains(MedicalCondition.injectionSupport) ||
      medicalConditions.contains(MedicalCondition.oxygenSupport) ||
      medicalConditions.contains(MedicalCondition.cannulaCare) ||
      medicalConditions.contains(MedicalCondition.catheterCare);
  if (isCritical) return CareTier.criticalCare;

  final isBedside = toiletAssistance.contains(ToiletAssistance.usesDiapers) ||
      toiletAssistance.contains(ToiletAssistance.usesBedPan) ||
      toiletAssistance.contains(ToiletAssistance.completeAssistance) ||
      toiletAssistance.contains(ToiletAssistance.others) ||
      careReceiver.feedingType == FeedingType.oralNeedsAssistance ||
      careReceiver.hasMedicalCondition;
  if (isBedside) return CareTier.bedsideCare;

  return CareTier.companionCare;
}
