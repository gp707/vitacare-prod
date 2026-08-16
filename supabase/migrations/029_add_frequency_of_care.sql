-- Admin now specifies how often care is needed alongside Hours Care Needed
-- (duty_type) — Daily or Monthly. 1 existing real job row backfills to
-- 'daily' (a reasonable default for its 12Hrs Night Shift duty type;
-- admin can change it anytime via the edit form) then the default is
-- dropped so every future insert must supply it explicitly (already
-- enforced at the DTO layer).

ALTER TABLE jobs ADD COLUMN frequency_of_care VARCHAR(10) NOT NULL DEFAULT 'daily'
  CHECK (frequency_of_care IN ('daily', 'monthly'));

ALTER TABLE jobs ALTER COLUMN frequency_of_care DROP DEFAULT;
