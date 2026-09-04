-- Admin's role in organisation requirements is now a pure approve/reject
-- click — there is nothing left for admin to set, so frequency_of_care/
-- salary_amount/schedule_type/start_date/end_date/schedule_repeat/
-- specific_days are dropped entirely (org's own duration_type — see
-- migration 066 — replaces the general sense of "when" these used to
-- convey, with no admin involvement). Matches this codebase's established
-- convention of fully dropping a removed field's column rather than
-- leaving an unused nullable remnant (see mobility/communication removal).
ALTER TABLE organisation_requirements DROP COLUMN frequency_of_care;
ALTER TABLE organisation_requirements DROP COLUMN salary_amount;
ALTER TABLE organisation_requirements DROP COLUMN schedule_type;
ALTER TABLE organisation_requirements DROP COLUMN start_date;
ALTER TABLE organisation_requirements DROP COLUMN end_date;
ALTER TABLE organisation_requirements DROP COLUMN schedule_repeat;
ALTER TABLE organisation_requirements DROP COLUMN specific_days;
