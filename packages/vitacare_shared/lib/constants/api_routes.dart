/// Endpoint path constants, relative to the API base URL (which includes the
/// /v1 prefix — see SPEC.md section 6.1). Extended as each phase's endpoints
/// are implemented on the backend.
class ApiRoutes {
  static const register = '/auth/register';
  static const registerIndividual = '/auth/register/individual';
  static const registerOrganisation = '/auth/register/organisation';
  static const loginCode = '/auth/login/code';
  static const loginEmail = '/auth/login/email';
  static const refresh = '/auth/refresh';
  static const logout = '/auth/logout';

  // NurseNow individual (patient/family) — same phone+code login as
  // caregiver (loginCode above), different registration/profile endpoints.
  static const individualMe = '/individual/me';
  static const individualRequirements = '/individual/requirements';
  static const individualProfilePhone = '/individual/profile/phone';
  static const individualProfileCode = '/individual/profile/code';
  static String individualRequirementApplications(String jobId) =>
      '/individual/requirements/$jobId/applications';
  static String individualRequirementApplicationDecide(String jobId, String applicationId) =>
      '/individual/requirements/$jobId/applications/$applicationId';

  // NurseNow organisation (hospital/rehab/clinic) — same phone+code login as
  // caregiver/individual. Unlike individual, an org may have many
  // simultaneous requirements — no one-live-at-a-time limit.
  static const organisationMe = '/organisation/me';
  static const organisationRequirements = '/organisation/requirements';
  static const organisationProfilePhone = '/organisation/profile/phone';
  static const organisationProfileCode = '/organisation/profile/code';
  static String organisationRequirementApplications(String requirementId) =>
      '/organisation/requirements/$requirementId/applications';
  static String organisationRequirementApplicationDecide(String requirementId, String applicationId) =>
      '/organisation/requirements/$requirementId/applications/$applicationId';

  // Caregiver-facing browse/apply for organisation requirements — a
  // separate section from the regular caregiverJobs list (explicit
  // decision: org openings are NOT merged into the existing Jobs tab).
  static const caregiverOrganisationRequirements = '/caregiver/organisation-requirements';
  static String caregiverOrganisationRequirementApply(String requirementId) =>
      '/caregiver/organisation-requirements/$requirementId/apply';

  static const caregiverProfile = '/caregiver/profile';
  static const caregiverProfilePhone = '/caregiver/profile/phone';
  static const caregiverProfileCode = '/caregiver/profile/code';
  static const caregiverProfileSelfie = '/caregiver/profile/selfie';
  static const caregiverProfileDocuments = '/caregiver/profile/documents';
  static const caregiverVerificationStatus = '/caregiver/verification-status';
  static const caregiverMarkAvailable = '/caregiver/mark-available';
  static const caregiverFcmToken = '/caregiver/fcm-token';
  static const caregiverJobs = '/caregiver/jobs';
  static const caregiverJobsAssigned = '/caregiver/jobs/assigned';

  static const appVersionCheck = '/app-versions/check';
}
