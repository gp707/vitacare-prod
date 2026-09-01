-- jobs.salary_amount becomes free text — NurseNow's Nurse Fee Guidance
-- (nursenow-app) now pre-fills it with a suggested rate looked up from the
-- admin-editable Rate Card, whose cells are themselves free text (e.g.
-- "26000 pm/867 per day\nTo\n30000 pm/1000 per day depending on
-- experience"), not a clean number. Admin's own job posting/editing UI is
-- unaffected in behavior — it still collects a plain number, just now
-- stored/sent as text. organisation_requirements.salary_amount is a
-- separate column on a separate table and is NOT changed here — Rate Card
-- guidance has never applied to Organisation postings.
ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_salary_amount_check;
ALTER TABLE jobs ALTER COLUMN salary_amount TYPE TEXT USING salary_amount::TEXT;
