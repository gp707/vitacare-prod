/**
 * Who may leave feedback on an engagement (one caregiver on one job): the caregiver
 * was accepted AND the work has actually started — the agreed cycle start date has
 * arrived, or a salary cycle has already been marked paid (which can only happen
 * once work started). Accepted-then-instantly-rejected, never-accepted and
 * not-yet-started engagements do not qualify; a caregiver rejected or closed out
 * AFTER the work started still does.
 */
export function canLeaveFeedback(params: {
  acceptedAt: Date | string | null;
  agreedStartDate: string | null;
  hasPaidCycle: boolean;
  today: string;
}): boolean {
  if (!params.acceptedAt) return false;
  if (params.hasPaidCycle) return true;
  return params.agreedStartDate != null && params.agreedStartDate <= params.today;
}
