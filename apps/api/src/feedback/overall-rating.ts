/** The bonus added to a caregiver's average rating: one and a half stars. */
export const OVERALL_RATING_BONUS = 1.5;

/**
 * A caregiver's overall rating, shown on her profile to everyone who can see it and as stars around
 * her picture in applicant lists: the average of the star ratings patients/families gave her, plus
 * one and a half stars, never above 5 (an average that is already 5 stays 5). Rounded to one
 * decimal. null when she has no ratings yet — then nothing is shown.
 */
export function overallRating(average: number | null | undefined): number | null {
  if (average == null || Number.isNaN(average)) return null;
  return Math.min(5, Math.round((average + OVERALL_RATING_BONUS) * 10) / 10);
}
