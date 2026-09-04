-- Adds duration_type to organisation_requirements — the org's own binary
-- choice of how long the engagement is expected to run: 'short_term'
-- ("Short Term (Few Days/Weeks Only)") or 'long_term' ("Long Term"). Org-
-- owned, set at creation alongside type_of_nurse/number_of_vacancies/
-- preferred_gender — never admin-set. Nullable at the DB level (no
-- backfill decision needed for the handful of pre-existing rows), but
-- required at the DTO layer for every new create/edit going forward, same
-- convention as several other fields documented in CLAUDE.md.
ALTER TABLE organisation_requirements ADD COLUMN duration_type VARCHAR(20)
  CHECK (duration_type IN ('short_term', 'long_term'));
