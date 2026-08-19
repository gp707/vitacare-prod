ALTER TABLE organisation_requirements
  ADD COLUMN schedule_repeat VARCHAR(10) CHECK (schedule_repeat IN ('weekly', 'monthly'));
