/// Mirrors the `care_receiver` object embedded in job creation/detail
/// responses (`POST /admin/jobs`, `GET /admin/jobs/:id`). 1:1 with a job —
/// not an independently reusable/searchable entity in this version.
class CareReceiverModel {
  final String id;
  final int age;
  final String gender;
  final int weightKg;
  final String mobility;
  final String communication;
  final String feedingType;
  final List<String> medicalAssistance;
  final bool hasMedicalCondition;
  final List<String> medicalConditions;
  final String? medicalConditionOther;
  final List<String> toiletAssistance;
  final String? toiletAssistanceOther;
  final bool requiresVitalMonitoring;
  final List<String> vitalMonitoringTypes;

  const CareReceiverModel({
    required this.id,
    required this.age,
    required this.gender,
    required this.weightKg,
    required this.mobility,
    required this.communication,
    required this.feedingType,
    required this.medicalAssistance,
    required this.hasMedicalCondition,
    required this.medicalConditions,
    this.medicalConditionOther,
    required this.toiletAssistance,
    this.toiletAssistanceOther,
    required this.requiresVitalMonitoring,
    required this.vitalMonitoringTypes,
  });

  factory CareReceiverModel.fromJson(Map<String, dynamic> json) => CareReceiverModel(
        id: json['id'] as String,
        age: json['age'] as int,
        gender: json['gender'] as String,
        weightKg: json['weight_kg'] as int,
        mobility: json['mobility'] as String,
        communication: json['communication'] as String,
        feedingType: json['feeding_type'] as String,
        medicalAssistance: List<String>.from(json['medical_assistance'] as List? ?? const []),
        hasMedicalCondition: json['has_medical_condition'] as bool? ?? false,
        medicalConditions: List<String>.from(json['medical_conditions'] as List? ?? const []),
        medicalConditionOther: json['medical_condition_other'] as String?,
        toiletAssistance: List<String>.from(json['toilet_assistance'] as List? ?? const []),
        toiletAssistanceOther: json['toilet_assistance_other'] as String?,
        requiresVitalMonitoring: json['requires_vital_monitoring'] as bool? ?? false,
        vitalMonitoringTypes: List<String>.from(json['vital_monitoring_types'] as List? ?? const []),
      );
}
