export 'package:vitacare_shared/vitacare_shared.dart' show PaginationMeta;

class AdminCaregiverListItem {
  final String userId;
  final String profileId;
  final int? caregiverNumber;
  final String fullName;
  final String phone;
  final String gender;
  final int age;
  final String? highestQualification;
  final String verificationStatus;
  final String createdAt;

  const AdminCaregiverListItem({
    required this.userId,
    required this.profileId,
    this.caregiverNumber,
    required this.fullName,
    required this.phone,
    required this.gender,
    required this.age,
    this.highestQualification,
    required this.verificationStatus,
    required this.createdAt,
  });

  factory AdminCaregiverListItem.fromJson(Map<String, dynamic> json) =>
      AdminCaregiverListItem(
        userId: json['user_id'] as String,
        profileId: json['profile_id'] as String,
        caregiverNumber: json['caregiver_number'] as int?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        gender: json['gender'] as String,
        age: json['age'] as int,
        highestQualification: json['highest_qualification'] as String?,
        verificationStatus: json['verification_status'] as String,
        createdAt: json['created_at'] as String,
      );
}

class AdminNotes {
  final String? internalNotes;
  final String? availabilityRemarks;

  const AdminNotes({
    this.internalNotes,
    this.availabilityRemarks,
  });

  factory AdminNotes.fromJson(Map<String, dynamic> json) => AdminNotes(
        internalNotes: json['internal_notes'] as String?,
        availabilityRemarks: json['availability_remarks'] as String?,
      );
}

class AdminCaregiverDetail {
  final String userId;
  final String profileId;
  final int? caregiverNumber;
  final String fullName;
  final String phone;
  final String? email;
  final String gender;
  final int age;
  final String? selfiePhotoUrl;
  final List<String> languages;
  final String? highestQualification;
  final String? religion;
  final String? qualificationDocumentUrl;
  final String? aadhaarDocumentUrl;
  final List<String> otherDocumentUrls;
  final bool termsAccepted;
  final String verificationStatus;
  final String? rejectionMessage;
  final bool hasPendingEdits;
  final List<String> preferredCities;
  final AdminNotes adminNotes;
  final String createdAt;
  final String? verifiedAt;

  const AdminCaregiverDetail({
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
    this.religion,
    this.qualificationDocumentUrl,
    this.aadhaarDocumentUrl,
    required this.otherDocumentUrls,
    required this.termsAccepted,
    required this.verificationStatus,
    this.rejectionMessage,
    required this.hasPendingEdits,
    required this.preferredCities,
    required this.adminNotes,
    required this.createdAt,
    this.verifiedAt,
  });

  factory AdminCaregiverDetail.fromJson(Map<String, dynamic> json) =>
      AdminCaregiverDetail(
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
        religion: json['religion'] as String?,
        qualificationDocumentUrl: json['qualification_document_url'] as String?,
        aadhaarDocumentUrl: json['aadhaar_document_url'] as String?,
        otherDocumentUrls:
            List<String>.from(json['other_document_urls'] as List? ?? const []),
        termsAccepted: json['terms_accepted'] as bool? ?? false,
        verificationStatus: json['verification_status'] as String,
        rejectionMessage: json['rejection_message'] as String?,
        hasPendingEdits: json['has_pending_edits'] as bool? ?? false,
        preferredCities:
            List<String>.from(json['preferred_cities'] as List? ?? const []),
        adminNotes: AdminNotes.fromJson(
            json['admin_notes'] as Map<String, dynamic>? ?? const {}),
        createdAt: json['created_at'] as String,
        verifiedAt: json['verified_at'] as String?,
      );
}

/// One previously-uploaded version of a document — selfie/qualification/
/// aadhaar/other are never overwritten in storage on replace, so every
/// upload ever made shows up here, newest first within its own document
/// type/slot. [signedUrl] is generated fresh per request (never persisted),
/// same as every other document link in this app.
class CaregiverDocumentVersion {
  final String id;
  final String documentType;
  final int? slotIndex;
  final String signedUrl;
  final String? uploadedByName;
  final String uploadedByRole;
  final String createdAt;

  const CaregiverDocumentVersion({
    required this.id,
    required this.documentType,
    this.slotIndex,
    required this.signedUrl,
    this.uploadedByName,
    required this.uploadedByRole,
    required this.createdAt,
  });

  factory CaregiverDocumentVersion.fromJson(Map<String, dynamic> json) =>
      CaregiverDocumentVersion(
        id: json['id'] as String,
        documentType: json['document_type'] as String,
        slotIndex: json['slot_index'] as int?,
        signedUrl: json['signed_url'] as String,
        uploadedByName: json['uploaded_by_name'] as String?,
        uploadedByRole: json['uploaded_by_role'] as String,
        createdAt: json['created_at'] as String,
      );
}
