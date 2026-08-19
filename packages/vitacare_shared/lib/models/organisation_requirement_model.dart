import 'job_model.dart';

/// Mirrors a row from GET /caregiver/organisation-requirements or
/// GET /organisation/requirements — the "exclusive" org posting shape (no
/// care_receiver, no city/area/duty_type of its own; city/area/
/// organisation_name below are the posting org's own registered location,
/// joined in server-side). Deliberately a separate model from JobModel —
/// see "NurseNow" in CLAUDE.md for why organisation requirements live in
/// their own tables.
class OrganisationRequirementModel {
  final String id;
  final int requirementNumber;
  final String postedBy;
  final String typeOfNurse;
  /// Null only while status is pending_review — admin sets it (along with
  /// [salaryAmount]) on approval.
  final String? frequencyOfCare;
  final int? salaryAmount;
  final String? startDate;
  final bool accommodationProvided;
  final bool foodProvided;
  final String? specialSkills;
  final String status;
  final String? rejectionReason;
  final String postedAt;
  /// Present on admin-facing and caregiver-facing list/detail responses —
  /// the posting org's own identity/location.
  final String? organisationName;
  final String? organisationType;
  final String? city;
  final String? area;
  /// The caregiver's own application to this requirement, if any — present
  /// on GET /caregiver/organisation-requirements (nullable, per-caregiver
  /// join) and GET /caregiver/organisation-requirements/assigned (always
  /// non-null there). Reuses JobModel's MyApplicationModel — identical
  /// shape, same underlying job_applications-style timeline columns.
  final MyApplicationModel? myApplication;

  const OrganisationRequirementModel({
    required this.id,
    required this.requirementNumber,
    required this.postedBy,
    required this.typeOfNurse,
    this.frequencyOfCare,
    this.salaryAmount,
    this.startDate,
    required this.accommodationProvided,
    required this.foodProvided,
    this.specialSkills,
    required this.status,
    this.rejectionReason,
    required this.postedAt,
    this.organisationName,
    this.organisationType,
    this.city,
    this.area,
    this.myApplication,
  });

  factory OrganisationRequirementModel.fromJson(Map<String, dynamic> json) => OrganisationRequirementModel(
        id: json['id'] as String,
        requirementNumber: json['requirement_number'] as int,
        postedBy: json['posted_by'] as String,
        typeOfNurse: json['type_of_nurse'] as String,
        frequencyOfCare: json['frequency_of_care'] as String?,
        salaryAmount: json['salary_amount'] as int?,
        startDate: json['start_date'] as String?,
        accommodationProvided: json['accommodation_provided'] as bool,
        foodProvided: json['food_provided'] as bool,
        specialSkills: json['special_skills'] as String?,
        status: json['status'] as String,
        rejectionReason: json['rejection_reason'] as String?,
        postedAt: json['posted_at'] as String,
        organisationName: json['organisation_name'] as String?,
        organisationType: json['organisation_type'] as String?,
        city: json['city'] as String?,
        area: json['area'] as String?,
        myApplication: json['my_application'] != null
            ? MyApplicationModel.fromJson(json['my_application'] as Map<String, dynamic>)
            : null,
      );
}

/// A single caregiver's application to an organisation requirement —
/// mirrors JobApplicationModel exactly (same shape, separate table).
class OrganisationRequirementApplicationModel {
  final String id;
  final String requirementId;
  final String profileId;
  final String status;
  final String? decidedBy;
  final String? decidedByName;
  final String fullName;
  final String phone;
  final String? appliedAt;
  final String? acceptedAt;
  final String? rejectedAt;
  final String? declineReason;
  final String updatedAt;

  const OrganisationRequirementApplicationModel({
    required this.id,
    required this.requirementId,
    required this.profileId,
    required this.status,
    this.decidedBy,
    this.decidedByName,
    required this.fullName,
    required this.phone,
    this.appliedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.declineReason,
    required this.updatedAt,
  });

  factory OrganisationRequirementApplicationModel.fromJson(Map<String, dynamic> json) =>
      OrganisationRequirementApplicationModel(
        id: json['id'] as String,
        requirementId: json['requirement_id'] as String,
        profileId: json['profile_id'] as String,
        status: json['status'] as String,
        decidedBy: json['decided_by'] as String?,
        decidedByName: json['decided_by_name'] as String?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        appliedAt: json['applied_at'] as String?,
        acceptedAt: json['accepted_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        declineReason: json['decline_reason'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}
