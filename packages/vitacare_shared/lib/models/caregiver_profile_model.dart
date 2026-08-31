/// Mirrors the API's GET /caregiver/profile response shape (SPEC.md 6.4).
/// All fields are always present in the response; unset ones are null.
class CaregiverProfileModel {
  final String userId;
  final String profileId;
  /// Human-friendly sequential id, e.g. 500 — display as "NUR-500" via
  /// [caregiverDisplayId].
  final int? caregiverNumber;
  final String fullName;
  final String phone;
  final String? email;
  final String gender;
  final int age;
  final String? selfiePhotoUrl;
  final List<String> languages;
  final String? highestQualification;
  final String? qualificationDocumentUrl;
  final String? aadhaarDocumentUrl;
  final List<String> otherDocumentUrls;
  final String? religion;
  final bool termsAccepted;
  final String verificationStatus;
  final String? rejectionMessage;
  final List<String> preferredCities;
  final String createdAt;

  const CaregiverProfileModel({
    required this.userId,
    required this.profileId,
    this.caregiverNumber,
    required this.fullName,
    required this.phone,
    this.email,
    required this.gender,
    required this.age,
    this.selfiePhotoUrl,
    required this.languages,
    this.highestQualification,
    this.qualificationDocumentUrl,
    this.aadhaarDocumentUrl,
    required this.otherDocumentUrls,
    this.religion,
    required this.termsAccepted,
    required this.verificationStatus,
    this.rejectionMessage,
    required this.preferredCities,
    required this.createdAt,
  });

  factory CaregiverProfileModel.fromJson(Map<String, dynamic> json) {
    return CaregiverProfileModel(
      userId: json['user_id'] as String,
      profileId: json['profile_id'] as String,
      caregiverNumber: json['caregiver_number'] as int?,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      gender: json['gender'] as String,
      age: json['age'] as int,
      selfiePhotoUrl: json['selfie_photo_url'] as String?,
      languages: List<String>.from(json['languages'] as List? ?? const []),
      highestQualification: json['highest_qualification'] as String?,
      qualificationDocumentUrl: json['qualification_document_url'] as String?,
      aadhaarDocumentUrl: json['aadhaar_document_url'] as String?,
      otherDocumentUrls: List<String>.from(json['other_document_urls'] as List? ?? const []),
      religion: json['religion'] as String?,
      termsAccepted: json['terms_accepted'] as bool? ?? false,
      verificationStatus: json['verification_status'] as String,
      rejectionMessage: json['rejection_message'] as String?,
      preferredCities: List<String>.from(json['preferred_cities'] as List? ?? const []),
      createdAt: json['created_at'] as String,
    );
  }

  /// Selfie and Aadhaar are both mandatory at registration; qualification
  /// and "other" documents are optional.
  bool get hasRequiredDocuments => aadhaarDocumentUrl != null;
}
