-- Caregiver-app previously showed a bare "You declined" for every
-- status='rejected' application, even when the real story was "applied,
-- then accepted by the job poster, then declined by them" (an admin
-- undoing a prior acceptance also lands on status='rejected', with no way
-- to tell the two cases apart from status alone). Adding explicit
-- per-transition timestamps lets the app show the real timeline with
-- dates; decided_by (already existing — NULL for the caregiver's own
-- apply/self-decline, set to the admin's id for an admin decision) lets it
-- distinguish "you declined" from "declined by the employer".

ALTER TABLE job_applications ADD COLUMN applied_at TIMESTAMPTZ;
ALTER TABLE job_applications ADD COLUMN accepted_at TIMESTAMPTZ;
ALTER TABLE job_applications ADD COLUMN rejected_at TIMESTAMPTZ;

-- Backfill applied_at from created_at (every row started as an application).
UPDATE job_applications SET applied_at = created_at;

-- Backfill accepted_at / rejected_at from the audit trail where available —
-- the most recent job_application_decided entry that transitioned this
-- application to that status.
UPDATE job_applications ja
SET accepted_at = (
  SELECT al.created_at FROM audit_logs al
  WHERE al.entity_type = 'job_applications'
    AND al.entity_id = ja.id
    AND al.action = 'job_application_decided'
    AND al.after_value ->> 'status' = 'accepted'
  ORDER BY al.created_at DESC
  LIMIT 1
);

UPDATE job_applications ja
SET rejected_at = (
  SELECT al.created_at FROM audit_logs al
  WHERE al.entity_type = 'job_applications'
    AND al.entity_id = ja.id
    AND al.action = 'job_application_decided'
    AND al.after_value ->> 'status' = 'rejected'
  ORDER BY al.created_at DESC
  LIMIT 1
)
WHERE ja.status = 'rejected';
