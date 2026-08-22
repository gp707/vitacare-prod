-- NurseNow individual/organisation registration now requires accepting
-- Terms & Conditions (a hyperlinked document, distinct per account type),
-- mirroring the caregiver registration flow's existing terms_accepted
-- column on caregiver_profiles. DEFAULT false only matters for this
-- backfill of any pre-existing rows — every new registration always sends
-- terms_accepted: true explicitly (enforced by RegisterIndividualDto/
-- RegisterOrganisationDto's @Equals(true) validator).
ALTER TABLE individual_profiles ADD COLUMN terms_accepted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE organisation_profiles ADD COLUMN terms_accepted BOOLEAN NOT NULL DEFAULT false;
