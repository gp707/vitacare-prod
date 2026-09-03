-- Communication removed from the product entirely — no longer collected,
-- stored, or displayed anywhere (admin-web's job posting form, caregiver-app's
-- job card, nursenow-app's requirement form, or the API). Already effectively
-- unused once admin-web's form stopped collecting it (every row was silently
-- defaulted to 'verbal' server-side); this removes the column outright.
ALTER TABLE care_receivers DROP COLUMN communication;
