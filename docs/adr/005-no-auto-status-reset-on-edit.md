# ADR-005: No Automatic Status Reset on Profile Edit

**Date:** 2026-08-01  
**Status:** Accepted

## Context

Originally, the system was designed so that any profile edit by a caregiver would automatically reset their `verification_status` back to `pending_verification`. This was intended to ensure admins always review the latest data.

However, this created problems:
- A caregiver fixing a typo in their address would lose their verified status.
- Minor edits (e.g., updating a photo) would require full re-verification.
- Caregivers already in active service could be disrupted by a status reset.

## Decision

Profile edits will not automatically reset `verification_status`. Instead:

1. When a caregiver edits their profile, the `has_pending_edits` flag is set to `true`.
2. Admins can filter/sort by `has_pending_edits` to see which profiles have been modified.
3. The admin manually decides whether the edit warrants a status reset (e.g., back to `pending_verification`) or can be acknowledged without changing status.
4. Once the admin reviews, they clear the `has_pending_edits` flag.

## Consequences

**Positive:**
- Caregivers are not disrupted by minor profile updates
- Admins have full control over whether an edit requires re-verification
- Reduces unnecessary re-verification work for the admin team
- Verified caregivers remain active and operational while edits are reviewed

**Negative:**
- Admins must actively monitor the `has_pending_edits` flag (mitigated by dashboard filters and notifications)
- A caregiver could theoretically change critical information without immediate re-verification (mitigated by admin notification on edit)
- Slightly more complex admin workflow compared to automatic reset
