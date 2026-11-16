-- Daily engagement push to patients/families and organisations: "N new caregivers
-- joined JustHeal today".
--
-- One row per (kind, day). The sender claims the day with
--   INSERT ... ON CONFLICT DO NOTHING RETURNING
-- BEFORE sending, so two API instances (or a restart at 10:00) can never both
-- send the same day's push. A failed send is therefore not retried that day.
--
-- Additive: safe to apply before the API that uses it is deployed.

CREATE TABLE IF NOT EXISTS daily_push_claims (
  kind        VARCHAR(50) NOT NULL,
  sent_on     DATE        NOT NULL,            -- the IST calendar day
  detail      JSONB       NOT NULL DEFAULT '{}'::jsonb,  -- e.g. real vs displayed count, for audit
  claimed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (kind, sent_on)
);
