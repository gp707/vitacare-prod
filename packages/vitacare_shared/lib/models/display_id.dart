/// Human-friendly sequential display ids — kept here (not duplicated per
/// app) so admin-web, caregiver-app, and nursenow-app all render identical
/// text. Backed by a raw integer sequence starting at 500 on each
/// respective profile table (migration 046); the prefix is applied only at
/// display time, same convention as jobs.job_number's "Job #<n>".
String? caregiverDisplayId(int? caregiverNumber) => caregiverNumber == null ? null : 'NUR-$caregiverNumber';

String? patientDisplayId(int? patientNumber) => patientNumber == null ? null : 'PAT-$patientNumber';

String? organisationDisplayId(int? orgNumber) => orgNumber == null ? null : 'ORG-$orgNumber';
