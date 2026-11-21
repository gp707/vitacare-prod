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

/** SQL fragment: a caregiver's overall rating (the average of the stars patients/families gave her over
 *  every engagement, plus one and a half stars, never above 5, one decimal) for the profile id in [profileIdExpr],
 *  or NULL when she has no ratings. Same rule as overallRating() in feedback/overall-rating.ts. Shown on
 *  her profile and around her picture in applicant lists. */
export const overallRatingSql = (profileIdExpr: string): string =>
  `(SELECT LEAST(5, ROUND(AVG(f.rating) + 1.5, 1))::float8
    FROM engagement_feedback f JOIN job_applications ra ON ra.id = f.application_id
    WHERE ra.profile_id = ${profileIdExpr} AND f.author_role = 'individual')`;
