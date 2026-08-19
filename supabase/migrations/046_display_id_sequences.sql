-- Human-friendly, sequential display IDs for organisations, individuals
-- (patients/family), and caregivers — same "raw integer column, prefix
-- applied at display time" convention as jobs.job_number/
-- organisation_requirements.requirement_number, except these three start
-- at 500 instead of 1. Displayed as ORG-<n> / PAT-<n> / NUR-<n>
-- respectively (see organisationDisplayId()/patientDisplayId()/
-- caregiverDisplayId() in packages/vitacare_shared).
CREATE SEQUENCE organisation_profiles_org_number_seq START WITH 500;
ALTER TABLE organisation_profiles
  ADD COLUMN org_number INTEGER NOT NULL DEFAULT nextval('organisation_profiles_org_number_seq') UNIQUE;
ALTER SEQUENCE organisation_profiles_org_number_seq OWNED BY organisation_profiles.org_number;

CREATE SEQUENCE individual_profiles_patient_number_seq START WITH 500;
ALTER TABLE individual_profiles
  ADD COLUMN patient_number INTEGER NOT NULL DEFAULT nextval('individual_profiles_patient_number_seq') UNIQUE;
ALTER SEQUENCE individual_profiles_patient_number_seq OWNED BY individual_profiles.patient_number;

CREATE SEQUENCE caregiver_profiles_caregiver_number_seq START WITH 500;
ALTER TABLE caregiver_profiles
  ADD COLUMN caregiver_number INTEGER NOT NULL DEFAULT nextval('caregiver_profiles_caregiver_number_seq') UNIQUE;
ALTER SEQUENCE caregiver_profiles_caregiver_number_seq OWNED BY caregiver_profiles.caregiver_number;
