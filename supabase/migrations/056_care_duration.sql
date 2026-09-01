-- How long a NurseNow individual's posted requirement is expected to last
-- (few days / few weeks / few months / long term). Nullable: only
-- NurseNow individual postings collect it (CreateIndividualRequirementDto,
-- required there); admin-posted jobs and every pre-existing row leave it
-- null. Admin's own edit/approve flow (JobsService.updateJob, shared with
-- approving an individual's pending_review posting) never touches this
-- column, so it's preserved untouched across approval -- see
-- JobsRepository.update()'s COALESCE.
ALTER TABLE jobs ADD COLUMN care_duration VARCHAR(20)
  CHECK (care_duration IN ('few_days', 'few_weeks', 'few_months', 'long_term'));
