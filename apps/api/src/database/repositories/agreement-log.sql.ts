/** SQL fragment: the history of agreed salary / start date changes for the application on the
 *  table aliased as [alias], oldest first, as [{salary, unit, start_date, at}] (migration 097).
 *  Shown in both people's activity log. */
export const agreementHistorySql = (alias: string): string =>
  `COALESCE((SELECT jsonb_agg(jsonb_build_object('salary', l.salary, 'unit', l.salary_unit, 'start_date', l.start_date, 'at', l.set_at) ORDER BY l.set_at, l.id)
             FROM job_application_agreement_log l WHERE l.application_id = ${alias}.id), '[]'::jsonb)`;

/** Same, for an organisation requirement application (migration 098). */
export const orgAgreementHistorySql = (alias: string): string =>
  `COALESCE((SELECT jsonb_agg(jsonb_build_object('salary', l.salary, 'unit', l.salary_unit, 'start_date', l.start_date, 'at', l.set_at) ORDER BY l.set_at, l.id)
             FROM organisation_application_agreement_log l WHERE l.application_id = ${alias}.id), '[]'::jsonb)`;
