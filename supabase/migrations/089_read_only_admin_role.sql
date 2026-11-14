-- New back-office role with limited write access. Additive: only widens the
-- allowed values, existing rows and roles are untouched. It falls into the
-- 'admin' phone bucket of users_phone_app_bucket_key (the CASE's ELSE).
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('super_admin', 'admin', 'read_only_admin', 'caregiver', 'individual', 'organisation'));
