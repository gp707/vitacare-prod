-- Job description becomes optional (Preferred Start Date becomes the
-- mandatory field in its place); relax the NOT NULL constraint so new
-- postings can omit it. No data loss — existing descriptions are untouched.
ALTER TABLE jobs
  ALTER COLUMN description DROP NOT NULL;
