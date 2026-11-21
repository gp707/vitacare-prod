/** SQL fragment: the feedback written by [authorRole] ('individual' = the patient/family,
 *  'caregiver') on the engagement behind the applications table aliased as [alias], as
 *  {rating, comment, created_at}, or NULL when none was written (migration 096). */
export const feedbackSql = (alias: string, authorRole: 'individual' | 'caregiver'): string =>
  `(SELECT jsonb_build_object('rating', f.rating, 'comment', f.comment, 'created_at', f.created_at)
    FROM engagement_feedback f WHERE f.application_id = ${alias}.id AND f.author_role = '${authorRole}')`;
