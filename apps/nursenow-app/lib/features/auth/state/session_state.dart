sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// No verification pipeline like a caregiver has — an individual/
/// organisation account is either logged in or it isn't. [isJobPostingBlocked]
/// gates the "post a requirement" action client-side (the server also
/// enforces it, JOB_010). [role] distinguishes which account type this is
/// (`UserRole.individual` or `UserRole.organisation`, decoded from the JWT
/// right after login/registration — POST /auth/login/code is shared across
/// both and doesn't say which one in its response body). The
/// organisation-only fields are null for an individual session.
class SessionAuthenticated extends SessionState {
  final String role;
  final String fullName;
  final String phone;
  final bool isJobPostingBlocked;
  final String? organisationName;
  final String? organisationType;
  final String? city;
  final String? area;
  /// Human-friendly sequential id — patientNumber for an individual,
  /// orgNumber for an organisation (whichever applies is non-null).
  /// Display via patientDisplayId()/organisationDisplayId().
  final int? patientNumber;
  final int? orgNumber;

  const SessionAuthenticated({
    required this.role,
    required this.fullName,
    required this.phone,
    required this.isJobPostingBlocked,
    this.organisationName,
    this.organisationType,
    this.city,
    this.area,
    this.patientNumber,
    this.orgNumber,
  });

  bool get isOrganisation => role == 'organisation';

  /// The bottom-nav "home" tab's route — a different screen per account
  /// type (JobsPostedScreen for Individual, RequirementsPostedScreen for
  /// Organisation), since the two have genuinely different data models.
  String get homeRoute => isOrganisation ? '/org-home' : '/home';
}
