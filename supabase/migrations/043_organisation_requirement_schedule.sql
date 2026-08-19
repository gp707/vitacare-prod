-- Organisation requirements gain a flexible admin-set schedule, replacing
-- the old daily-only single start_date. Admin picks exactly one mode on
-- approval: a continuous date range (start_date + end_date) or a set of
-- specific calendar days of the month (e.g. 3rd/12th/20th, for
-- non-continuous recurring shifts). This is deliberately organisation-only
-- — regular jobs (admin/individual postings) keep their existing single
-- start_date field unchanged.
ALTER TABLE organisation_requirements
  ADD COLUMN schedule_type VARCHAR(20) CHECK (schedule_type IN ('date_range', 'specific_days')),
  ADD COLUMN end_date DATE,
  ADD COLUMN specific_days INTEGER[];

-- start_date already exists (added in 041) and is reused as the date_range
-- mode's start — no new column needed for that half.
