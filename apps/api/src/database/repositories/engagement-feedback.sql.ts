/** SQL fragment: the feedback written by [authorRole] ('individual' = the patient/family,
 *  'caregiver') on the engagement behind the applications table aliased as [alias], as
 *  {rating, comment, created_at}, or NULL when none was written (migration 096). */
export const feedbackSql = (
  alias: string,
  authorRole: 'individual' | 'caregiver',
  /** false = the star rating only, with the comment always NULL (what a caregiver may see of the
   *  family's feedback about them: the stars, never the written comment). */
  withComment = true,
): string =>
  `(SELECT jsonb_build_object('rating', f.rating, 'comment', ${withComment ? 'f.comment' : 'NULL::text'}, 'created_at', f.created_at)
    FROM engagement_feedback f WHERE f.application_id = ${alias}.id AND f.author_role = '${authorRole}')`;
