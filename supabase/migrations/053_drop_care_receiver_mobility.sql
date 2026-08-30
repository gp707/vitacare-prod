-- Mobility field removed from the product entirely — no longer collected,
-- stored, or displayed anywhere (admin-web's job posting form, caregiver-app's
-- job card, nursenow-app's requirement form, or the API). Superseded by
-- nothing in particular; simply dropped as part of restructuring NurseNow's
-- Post/Edit Requirement form into clearly separated "Patient Details" /
-- "Care Preferences" sections.
ALTER TABLE care_receivers DROP COLUMN mobility;
