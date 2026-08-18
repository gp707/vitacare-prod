/// Endpoint path constants, relative to the API base URL (which includes the
/// /v1 prefix — see SPEC.md section 6.1). Extended as each phase's endpoints
/// are implemented on the backend.
class ApiRoutes {
  static const register = '/auth/register';
  static const registerIndividual = '/auth/register/individual';
  static const loginCode = '/auth/login/code';
  static const loginEmail = '/auth/login/email';
  static const refresh = '/auth/refresh';
  static const logout = '/auth/logout';

  // NurseNow individual (patient/family) — same phone+code login as
  // caregiver (loginCode above), different registration/profile endpoints.
  static const individualMe = '/individual/me';
  static const individualRequirements = '/individual/requirements';
  static String individualRequirementApplications(String jobId) =>
      '/individual/requirements/$jobId/applications';
  static String individualRequirementApplicationDecide(String jobId, String applicationId) =>
      '/individual/requirements/$jobId/applications/$applicationId';

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
