-- Relaxes phone uniqueness from global (one account per phone, across every
-- role) to per-app-bucket: a phone can have at most one NurseJobs account
-- (role='caregiver') AND, independently, at most one NurseNow account
-- (role IN ('individual','organisation')) AND, independently, at most one
-- admin-side account (role IN ('admin','super_admin')). These are fully
-- separate, unlinked accounts that happen to share a phone number — no
-- profile data is shared or merged between them.
ALTER TABLE users DROP CONSTRAINT users_phone_key;

CREATE UNIQUE INDEX users_phone_app_bucket_key ON users (
  phone,
  (CASE
     WHEN role = 'caregiver' THEN 'nursejobs'
     WHEN role IN ('individual', 'organisation') THEN 'nursenow'
     ELSE 'admin'
   END)
);
