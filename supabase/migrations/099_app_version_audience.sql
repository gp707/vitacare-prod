-- Who a forced minimum app version applies to (one audience per platform row).
--
-- Until now a platform's minimum version applied to everybody. Now admin can choose:
--   audience_mode = 'all'       -> everyone, exactly as before (the default for every existing row)
--   audience_mode = 'selected'  -> only the chosen CATEGORIES (patients, caregivers, hospitals, rehabs,
--                                  clinics, agencies) and/or the specific ACCOUNTS (user ids) listed.
--
-- Categories: 'caregiver', 'individual' (patients/families) or an organisation type ('hospital',
-- 'rehab', 'clinic', 'agency'). A selected-audience rule is evaluated for a signed-in account; the app
-- re-checks every time an account signs in, so it cannot be dodged by being logged out at launch.
--
-- Additive, with defaults that keep every existing row behaving exactly as today: safe to apply
-- before the backend that uses it is deployed.

ALTER TABLE app_min_versions
  ADD COLUMN IF NOT EXISTS audience_mode       VARCHAR(10) NOT NULL DEFAULT 'all',
  ADD COLUMN IF NOT EXISTS audience_categories TEXT[]      NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS audience_user_ids   UUID[]      NOT NULL DEFAULT '{}';

ALTER TABLE app_min_versions DROP CONSTRAINT IF EXISTS app_min_versions_audience_mode_check;
ALTER TABLE app_min_versions ADD CONSTRAINT app_min_versions_audience_mode_check
  CHECK (audience_mode IN ('all', 'selected'));

ALTER TABLE app_min_versions DROP CONSTRAINT IF EXISTS app_min_versions_audience_categories_check;
ALTER TABLE app_min_versions ADD CONSTRAINT app_min_versions_audience_categories_check
  CHECK (audience_categories <@ ARRAY['caregiver', 'individual', 'hospital', 'rehab', 'clinic', 'agency']::text[]);
