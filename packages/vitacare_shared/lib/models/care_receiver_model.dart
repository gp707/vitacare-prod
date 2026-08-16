/// Mirrors the `care_receiver` object embedded in job creation/detail
/// responses (`POST /admin/jobs`, `GET /admin/jobs/:id`). 1:1 with a job —
/// not an independently reusable/searchable entity in this version.
class CareReceiverModel {
  final String id;
  final String mobility;
  final String communication;
  final String feedingType;
  final bool? tubeFeedingNeedsAssistance;
  final List<String> medicalAssistance;
  final bool hasMedicalCondition;
  final List<String> medicalConditions;
  final String? medicalInfo;

  const CareReceiverModel({
    required this.id,
    required this.mobility,
    required this.communication,
    required this.feedingType,
    this.tubeFeedingNeedsAssistance,
    required this.medicalAssistance,
    required this.hasMedicalCondition,
    required this.medicalConditions,
    this.medicalInfo,
  });

  factory CareReceiverModel.fromJson(Map<String, dynamic> json) => CareReceiverModel(
        id: json['id'] as String,
        mobility: json['mobility'] as String,
        communication: json['communication'] as String,
        feedingType: json['feeding_type'] as String,
        tubeFeedingNeedsAssistance: json['tube_feeding_needs_assistance'] as bool?,
        medicalAssistance: List<String>.from(json['medical_assistance'] as List? ?? const []),
        hasMedicalCondition: json['has_medical_condition'] as bool? ?? false,
        medicalConditions: List<String>.from(json['medical_conditions'] as List? ?? const []),
        medicalInfo: json['medical_info'] as String?,
      );
}
