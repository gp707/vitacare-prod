export interface ApplicantSummary {
  total: number;
  awaiting: number;
  accepted: number;
  completed: number;
  rejected_by_caregiver: number;
  rejected_by_employer: { name: string; role: string }[];
}

/** Per-job / per-requirement applicant tally for admin's list rows: how many
 *  are waiting, accepted, closed by the caregiver, and rejected — split into
 *  "caregiver declined themselves" (decided_by IS NULL) and "rejected by
 *  <name>" (the deciding patient, organisation or admin). A caregiver who
 *  declines after an earlier employer rejection keeps the old decided_by (re-
 *  applying never clears it), so that rare case counts as an employer one. */
export function applicantSummarySql(table: 'job_applications' | 'organisation_requirement_applications', fk: 'job_id' | 'requirement_id', parentAlias: string): string {
  return `(SELECT jsonb_build_object(
      'total', COUNT(*)::int,
      'awaiting', (COUNT(*) FILTER (WHERE a.status = 'applied'))::int,
      'accepted', (COUNT(*) FILTER (WHERE a.status = 'accepted'))::int,
      'completed', (COUNT(*) FILTER (WHERE a.status = 'completed'))::int,
      'rejected_by_caregiver', (COUNT(*) FILTER (WHERE a.status = 'rejected' AND a.decided_by IS NULL))::int,
      'rejected_by_employer', COALESCE(
        jsonb_agg(jsonb_build_object('name', du.full_name, 'role', du.role))
          FILTER (WHERE a.status = 'rejected' AND a.decided_by IS NOT NULL),
        '[]'::jsonb)
    )
    FROM ${table} a
    LEFT JOIN users du ON du.id = a.decided_by
    WHERE a.${fk} = ${parentAlias}.id) AS applicant_summary`;
}
