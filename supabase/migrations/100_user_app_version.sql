-- Which app version each account is running, so admin can see who is on what version.
--
-- Filled by the server whenever the app does its version check while signed in (the app does this at
-- every launch and every sign-in): platform ('android' | 'ios'), the version it reported, and when.
-- An account that has not been seen on a build that reports this has NULLs (shown as "not reported yet").
--
-- Additive and nullable: safe to apply before the backend that uses it is deployed.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS app_platform        VARCHAR(10),
  ADD COLUMN IF NOT EXISTS app_version         VARCHAR(20),
  ADD COLUMN IF NOT EXISTS app_version_seen_at TIMESTAMPTZ;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_app_platform_check;
ALTER TABLE users ADD CONSTRAINT users_app_platform_check
  CHECK (app_platform IS NULL OR app_platform IN ('android', 'ios'));

CREATE INDEX IF NOT EXISTS idx_users_app_version ON users (app_platform, app_version) WHERE app_version IS NOT NULL;
