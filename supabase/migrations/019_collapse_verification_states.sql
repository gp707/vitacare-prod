-- ============================================
-- Collapse the onboarding funnel: all caregiver fields (including what
-- used to be "Advanced Details") are now collected in one registration,
-- so call_verified, pending_verification, and in_process are no longer
-- distinct states — the flow is pending_call -> available/rejected,
-- decided in a single admin approval.
-- ============================================

-- Remap any rows sitting in a removed state back to pending_call before the
-- new CHECK constraint goes on (pending_verification/in_process folded into
-- the same single pre-decision state as call_verified).
UPDATE caregiver_profiles SET verification_status = 'pending_call'
  WHERE verification_status IN ('call_verified', 'pending_verification', 'in_process');

ALTER TABLE caregiver_profiles DROP CONSTRAINT IF EXISTS caregiver_profiles_verification_status_check;
ALTER TABLE caregiver_profiles ADD CONSTRAINT caregiver_profiles_verification_status_check
  CHECK (verification_status IN ('pending_call', 'available', 'unavailable', 'assigned', 'rejected'));

ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS call_verified_at;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS call_verified_by;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS advanced_details_completed;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS submitted_at;
