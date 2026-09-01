-- Rate Card becomes 2 rows (daily / monthly) instead of a singleton, so
-- admin can maintain separate daily and monthly salary guidance instead of
-- one grid whose cells already mix both into free text (e.g. "26000
-- pm/867 per day"). Same "one row per key" pattern as app_min_versions
-- (platform) — frequency_of_care reuses the existing FrequencyOfCare enum
-- ('daily'/'monthly') as the primary key, same convention.
--
-- The existing singleton's content doesn't split mechanically (several
-- cells already combine daily and monthly figures in one string), so both
-- new rows start as an exact duplicate of it, with " — Daily"/" — Monthly"
-- appended to the title so the two are distinguishable immediately, even
-- before an admin trims each grid down to just its own frequency's figures.

DROP TABLE rate_card;

CREATE TABLE rate_card (
  frequency_of_care VARCHAR(10) PRIMARY KEY CHECK (frequency_of_care IN ('daily', 'monthly')),
  title TEXT NOT NULL,
  column_labels TEXT[] NOT NULL,
  row_labels TEXT[] NOT NULL,
  cells JSONB NOT NULL,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO rate_card (frequency_of_care, title, column_labels, row_labels, cells) VALUES
(
  'daily',
  'Salary Guidelines (12 hrs/24 hrs duty) — Daily',
  ARRAY['Companion care', 'Bedside Care', 'Critical Care'],
  ARRAY['Care', 'Nursing students/Nursing with backlogs', 'Nurses (Nursing completed/Registered/Unregistered)'],
  '[
    ["26000 pm/867 per day\nTo \n30000 pm/1000 per day\ndepending on experience", "28000 pm/933 per day \nTo \n32000 pm/1067 per day", "32000 pm/1067 per day\nTo\n35000-42000 pm (depending on years of experience)"],
    ["28000 pm/933 per day", "30000 pm/1000 per day", "32000 pm/1067 per day"],
    ["30000 pm/1000 per day", "32000 pm/1067 per day", "35000-42000 pm (depending on years of experience)"]
  ]'::jsonb
),
(
  'monthly',
  'Salary Guidelines (12 hrs/24 hrs duty) — Monthly',
  ARRAY['Companion care', 'Bedside Care', 'Critical Care'],
  ARRAY['Care', 'Nursing students/Nursing with backlogs', 'Nurses (Nursing completed/Registered/Unregistered)'],
  '[
    ["26000 pm/867 per day\nTo \n30000 pm/1000 per day\ndepending on experience", "28000 pm/933 per day \nTo \n32000 pm/1067 per day", "32000 pm/1067 per day\nTo\n35000-42000 pm (depending on years of experience)"],
    ["28000 pm/933 per day", "30000 pm/1000 per day", "32000 pm/1067 per day"],
    ["30000 pm/1000 per day", "32000 pm/1067 per day", "35000-42000 pm (depending on years of experience)"]
  ]'::jsonb
);
