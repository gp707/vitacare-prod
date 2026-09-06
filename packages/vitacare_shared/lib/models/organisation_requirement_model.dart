import 'job_model.dart';

/// Mirrors a row from GET /caregiver/organisation-requirements or
/// GET /organisation/requirements — the "exclusive" org posting shape (no
/// care_receiver, no city/area/duty_type of its own; city/area/
/// organisation_name below are the posting org's own registered location,
/// joined in server-side). Deliberately a separate model from JobModel —
/// see "NurseNow" in CLAUDE.md for why organisation requirements live in
/// their own tables. Every field here is org-owned, set at creation or via
/// the org's own self-edit — admin's entire role is a pure approve/reject
/// click, with no fields of its own at all.
class OrganisationRequirementModel {
  final String id;
  final int requirementNumber;
  final String postedBy;
  final String typeOfNurse;
  /// Free text elaboration, only ever non-null when [typeOfNurse] is
  /// 'others' — mirrors CareReceiverModel's medicalConditionOther.
  final String? typeOfNurseOther;
  final bool accommodationProvided;
  final bool foodProvided;
  final String? specialSkills;
  /// Org-set at creation, 1-49, defaults to 1 — how many caregivers this one
  /// requirement is looking to fill.
  final int numberOfVacancies;
  /// Org-set at creation. Null = no preference. Mirrors JobModel's own
  /// preferredGender exactly (male/female only — never 'other').
  final String? preferredGender;
  /// Org-set at creation — 'short_term' or 'long_term'. See
  /// RequirementDuration in enums.dart.
  final String? durationType;
  final String status;
  final String? rejectionReason;
  /// Set once the org cancels this requirement themselves (distinct from
  /// [rejectionReason], which is an admin decision) — mirrors JobModel's
  /// own cancelledAt.
  final String? cancelledAt;
  final String postedAt;
  /// Present on admin-facing and caregiver-facing list/detail responses —
  /// the posting org's own identity/location.
  final String? organisationName;
  final String? organisationType;
  final String? city;
  final String? area;
  /// The posting organisation's own contact phone — mirrors JobModel's
  /// jobPoster.phone, but flattened onto this model rather than nested,
  /// since organisationName already carries the "who" half. Only ever
  /// present on GET /caregiver/organisation-requirements/assigned, once
  /// the caregiver has actually been accepted — never on the browse list.
  final String? organisationPhone;
  /// The caregiver's own application to this requirement, if any — present
  /// on GET /caregiver/organisation-requirements (nullable, per-caregiver
  /// join) and GET /caregiver/organisation-requirements/assigned (always
  /// non-null there). Reuses JobModel's MyApplicationModel — identical
  /// shape, same underlying job_applications-style timeline columns.
  final MyApplicationModel? myApplication;
  /// Total distinct caregivers who have ever applied — shown on
  /// caregiver-app's browse list as a plain "N applied" count, same
  /// convention as JobModel.applicantCount. Only present on
  /// GET /caregiver/organisation-requirements's response.
  final int? applicantCount;

  const OrganisationRequirementModel({
    required this.id,
    required this.requirementNumber,
    required this.postedBy,
    required this.typeOfNurse,
    this.typeOfNurseOther,
    required this.accommodationProvided,
    required this.foodProvided,
    this.specialSkills,
    required this.numberOfVacancies,
    this.preferredGender,
    this.durationType,
    required this.status,
    this.rejectionReason,
    this.cancelledAt,
    required this.postedAt,
    this.organisationName,
    this.organisationType,
    this.city,
    this.area,
    this.organisationPhone,
    this.myApplication,
    this.applicantCount,
  });

  factory OrganisationRequirementModel.fromJson(Map<String, dynamic> json) => OrganisationRequirementModel(
        id: json['id'] as String,
        requirementNumber: json['requirement_number'] as int,
        postedBy: json['posted_by'] as String,
        typeOfNurse: json['type_of_nurse'] as String,
        typeOfNurseOther: json['type_of_nurse_other'] as String?,
        accommodationProvided: json['accommodation_provided'] as bool,
        foodProvided: json['food_provided'] as bool,
        specialSkills: json['special_skills'] as String?,
        numberOfVacancies: json['number_of_vacancies'] as int,
        preferredGender: json['preferred_gender'] as String?,
        durationType: json['duration_type'] as String?,
        status: json['status'] as String,
        rejectionReason: json['rejection_reason'] as String?,
        cancelledAt: json['cancelled_at'] as String?,
        postedAt: json['posted_at'] as String,
        organisationName: json['organisation_name'] as String?,
        organisationType: json['organisation_type'] as String?,
        city: json['city'] as String?,
        area: json['area'] as String?,
        organisationPhone: json['organisation_phone'] as String?,
        myApplication: json['my_application'] != null
            ? MyApplicationModel.fromJson(json['my_application'] as Map<String, dynamic>)
            : null,
        applicantCount: json['applicant_count'] as int?,
      );

  /// Mirrors JobModel.isCancelled — set once the org cancels this
  /// requirement themselves via the self-cancel endpoint.
  bool get isCancelled => cancelledAt != null;
}

/// Human-friendly display id for an organisation requirement —
/// "ORG-JOB-<n>" (migration 047 rebased requirementNumber's own sequence
/// to start at 500), replacing the old generic "Requirement #<n>" label
/// everywhere. Kept here, not duplicated per app.
String organisationJobDisplayId(OrganisationRequirementModel requirement) =>
    'ORG-JOB-${requirement.requirementNumber}';

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
  /// Set once the caregiver closes this same requirement themselves after
  /// being accepted (POST /caregiver/organisation-requirements/:id/complete)
  /// — mirrors JobApplicationModel's own completedAt.
  final String? completedAt;
  final String? declineReason;
  /// Only ever set once [status] is 'completed' — the caregiver's own
  /// reason for closing this requirement (CaregiverCloseReason), defaults
  /// to 'no_reason' server-side rather than staying null. Visible to the
  /// organisation here, same as MyApplicationModel shows it to the
  /// caregiver themselves.
  final String? closeReason;
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
    this.completedAt,
    this.declineReason,
    this.closeReason,
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
        completedAt: json['completed_at'] as String?,
        declineReason: json['decline_reason'] as String?,
        closeReason: json['close_reason'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}
