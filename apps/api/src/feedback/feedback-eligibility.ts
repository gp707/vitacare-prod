/**
 * Who may leave feedback on an engagement (one caregiver on one job): the caregiver
 * was accepted AND the work has actually started — the agreed start date has arrived.
 * Accepted-then-instantly-rejected, never-accepted and not-yet-started engagements do
 * not qualify; a caregiver rejected or closed out AFTER the work started still does
 * (the agreed start date is kept through rejection and closing duty).
 */
export function canLeaveFeedback(params: {
  acceptedAt: Date | string | null;
  agreedStartDate: string | null;
  today: string;
}): boolean {
  if (!params.acceptedAt) return false;
  return params.agreedStartDate != null && params.agreedStartDate <= params.today;
}
