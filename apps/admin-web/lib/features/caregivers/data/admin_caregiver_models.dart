export 'package:vitacare_shared/vitacare_shared.dart' show PaginationMeta;

class AdminCaregiverListItem {
  final String userId;
  final String profileId;
  final String fullName;
  final String phone;
  final String gender;
  final int age;
  final String? highestQualification;
  final List<String> serviceModes;
  final List<String> workTypes;
  final String verificationStatus;
  final String createdAt;

  const AdminCaregiverListItem({
    required this.userId,
    required this.profileId,
    required this.fullName,
    required this.phone,
    required this.gender,
    required this.age,
    this.highestQualification,
    required this.serviceModes,
    required this.workTypes,
    required this.verificationStatus,
    required this.createdAt,
  });

  factory AdminCaregiverListItem.fromJson(Map<String, dynamic> json) => AdminCaregiverListItem(
        userId: json['user_id'] as String,
        profileId: json['profile_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        gender: json['gender'] as String,
        age: json['age'] as int,
        highestQualification: json['highest_qualification'] as String?,
        serviceModes: List<String>.from(json['service_modes'] as List? ?? const []),
        workTypes: List<String>.from(json['work_types'] as List? ?? const []),
        verificationStatus: json['verification_status'] as String,
        createdAt: json['created_at'] as String,
      );
}

class AdminNotes {
  final String? internalNotes;
  final num? rate24hrsLiveIn;
  final num? rate12hrsPg;
  final String? availabilityRemarks;

  const AdminNotes({
    this.internalNotes,
    this.rate24hrsLiveIn,
    this.rate12hrsPg,
    this.availabilityRemarks,
  });

  factory AdminNotes.fromJson(Map<String, dynamic> json) => AdminNotes(
        internalNotes: json['internal_notes'] as String?,
        rate24hrsLiveIn: json['rate_24hrs_live_in'] as num?,
        rate12hrsPg: json['rate_12hrs_pg'] as num?,
        availabilityRemarks: json['availability_remarks'] as String?,
      );
}

class AdminCaregiverDetail {
  final String userId;
  final String profileId;
  final String fullName;
  final String phone;
  final String? email;
  final String gender;
  final int age;
  final String? selfiePhotoUrl;
  final List<String> languages;
  final List<String> serviceModes;
  final List<String> workTypes;
  final num? salary;
  final String? highestQualification;
  final String? religion;
  final String? fatherName;
  final String? fatherPhone;
  final String? qualificationDocumentUrl;
  final String? aadhaarDocumentUrl;
  final List<String> otherDocumentUrls;
  final String? currentAddress;
  final bool termsAccepted;
  final String verificationStatus;
  final String? rejectionMessage;
  final bool advancedDetailsCompleted;
  final bool hasPendingEdits;
  final List<String> preferredCities;
  final String? notes;
  final AdminNotes adminNotes;
  final String createdAt;
  final String? submittedAt;
  final String? verifiedAt;

  const AdminCaregiverDetail({
    required this.userId,
    required this.profileId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.gender,
    required this.age,
    this.selfiePhotoUrl,
    required this.languages,
    required this.serviceModes,
    required this.workTypes,
    this.salary,
    this.highestQualification,
    this.religion,
    this.fatherName,
    this.fatherPhone,
    this.qualificationDocumentUrl,
    this.aadhaarDocumentUrl,
    required this.otherDocumentUrls,
    this.currentAddress,
    required this.termsAccepted,
    required this.verificationStatus,
    this.rejectionMessage,
    required this.advancedDetailsCompleted,
    required this.hasPendingEdits,
    required this.preferredCities,
    this.notes,
    required this.adminNotes,
    required this.createdAt,
    this.submittedAt,
    this.verifiedAt,
  });

  factory AdminCaregiverDetail.fromJson(Map<String, dynamic> json) => AdminCaregiverDetail(
        userId: json['user_id'] as String,
        profileId: json['profile_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        email: json['email'] as String?,
        gender: json['gender'] as String,
        age: json['age'] as int,
        selfiePhotoUrl: json['selfie_photo_url'] as String?,
        languages: List<String>.from(json['languages'] as List? ?? const []),
        serviceModes: List<String>.from(json['service_modes'] as List? ?? const []),
        workTypes: List<String>.from(json['work_types'] as List? ?? const []),
        salary: json['salary'] as num?,
        highestQualification: json['highest_qualification'] as String?,
        religion: json['religion'] as String?,
        fatherName: json['father_name'] as String?,
        fatherPhone: json['father_phone'] as String?,
        qualificationDocumentUrl: json['qualification_document_url'] as String?,
        aadhaarDocumentUrl: json['aadhaar_document_url'] as String?,
        otherDocumentUrls: List<String>.from(json['other_document_urls'] as List? ?? const []),
        currentAddress: json['current_address'] as String?,
        termsAccepted: json['terms_accepted'] as bool? ?? false,
        verificationStatus: json['verification_status'] as String,
        rejectionMessage: json['rejection_message'] as String?,
        advancedDetailsCompleted: json['advanced_details_completed'] as bool? ?? false,
        hasPendingEdits: json['has_pending_edits'] as bool? ?? false,
        preferredCities: List<String>.from(json['preferred_cities'] as List? ?? const []),
        notes: json['notes'] as String?,
        adminNotes: AdminNotes.fromJson(json['admin_notes'] as Map<String, dynamic>? ?? const {}),
        createdAt: json['created_at'] as String,
        submittedAt: json['submitted_at'] as String?,
        verifiedAt: json['verified_at'] as String?,
      );
}
