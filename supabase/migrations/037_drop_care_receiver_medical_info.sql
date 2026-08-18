-- "Important information for the caregiver" (free text) has been removed
-- from the product entirely — no longer collected, stored, or displayed
-- anywhere (admin-web, caregiver-app, or the API).
ALTER TABLE care_receivers DROP COLUMN medical_info;
