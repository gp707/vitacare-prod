-- Patient/family self-service job cancellation (NurseNow individual).
-- Distinct from a normal close (filled) or admin reject (rejection_reason):
-- cancelled_at marks a patient-initiated cancellation. Once set, the
-- individual's own view of past applicants/phone numbers is hidden (see
-- IndividualService.getMyRequirementApplications/getApplicantProfile) —
-- the underlying job_applications rows are left intact for audit purposes,
-- only the individual's own read is gated.
ALTER TABLE jobs ADD COLUMN cancelled_at TIMESTAMPTZ;
