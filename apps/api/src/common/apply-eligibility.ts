import { VerificationStatus } from '@vitacare/shared-constants';

/**
 * Caregivers in one of these statuses can apply to a job or organisation
 * requirement; `unavailable` / `pending_call` / `rejected` cannot. One rule,
 * shared by the apply endpoints and by the "new job" push, so a caregiver is
 * only ever told about a job they are actually able to apply to. A caregiver
 * who is already working (`assigned`) can take on another job, so they are
 * included.
 */
export const APPLY_ELIGIBLE_STATUSES: VerificationStatus[] = [
  VerificationStatus.AVAILABLE,
  VerificationStatus.ASSIGNED,
];
