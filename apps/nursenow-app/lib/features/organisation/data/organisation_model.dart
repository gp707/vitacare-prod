/// Mirrors GET /organisation/me.
class OrganisationModel {
  final String userId;
  final String organisationName;
  final String contactPersonName;
  final String organisationType;
  final String city;
  final String area;
  final String phone;
  final bool isJobPostingBlocked;

  const OrganisationModel({
    required this.userId,
    required this.organisationName,
    required this.contactPersonName,
    required this.organisationType,
    required this.city,
    required this.area,
    required this.phone,
    required this.isJobPostingBlocked,
  });

  factory OrganisationModel.fromJson(Map<String, dynamic> json) => OrganisationModel(
        userId: json['user_id'] as String,
        organisationName: json['organisation_name'] as String,
        contactPersonName: json['contact_person_name'] as String,
        organisationType: json['organisation_type'] as String,
        city: json['city'] as String,
        area: json['area'] as String,
        phone: json['phone'] as String,
        isJobPostingBlocked: json['is_job_posting_blocked'] as bool,
      );
}
