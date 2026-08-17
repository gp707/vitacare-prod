-- Salary can now be a daily or monthly figure depending on
-- frequency_of_care — salary_monthly's name would lie about its contents
-- for a 'daily' job, so rename it to the frequency-neutral salary_amount.
-- Pure rename, no data change; existing rows keep their values.
ALTER TABLE jobs RENAME COLUMN salary_monthly TO salary_amount;
ALTER TABLE jobs RENAME CONSTRAINT jobs_salary_monthly_check TO jobs_salary_amount_check;
