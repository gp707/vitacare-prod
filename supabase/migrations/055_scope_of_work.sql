-- Scope of Work: a single admin-editable set of 3 cumulative bullet lists
-- (Companion Care / Bedside Care / Critical Care), shown to caregivers
-- (NurseJobs) via a per-job popup -- which tier applies to a given job is
-- DERIVED from that job's care_receiver fields (see
-- packages/vitacare_shared/lib/models/care_tier.dart), never manually
-- picked. Deliberately NOT shown on Organisation (hospital/rehab/clinic)
-- postings, which have no care_receiver to derive a tier from -- same
-- exclusion rate_card already applies for the same reason.
-- Singleton row (id fixed to 1), same convention as rate_card.
CREATE TABLE scope_of_work (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  companion_care TEXT[] NOT NULL,
  bedside_care TEXT[] NOT NULL,
  critical_care TEXT[] NOT NULL,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO scope_of_work (id, companion_care, bedside_care, critical_care) VALUES (
  1,
  ARRAY[
    'Emotional companionship',
    'Walking & mobility support',
    'Medication reminders',
    'Meal assistance',
    'Grooming & hygiene support',
    'Daily routine assistance'
  ],
  ARRAY[
    'Diaper changing & hygiene care',
    'Feeding assistance',
    'Bedpan & commode support',
    'Repositioning support',
    'Mobility & transfer assistance',
    'Recovery monitoring'
  ],
  ARRAY[
    'Catheter care',
    'Tube feeding support',
    'Insulin & injections',
    'Vitals monitoring',
    'Oxygen & suction support',
    'Wound & pressure sore care'
  ]
);

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided', 'admin_document_uploaded', 'admin_role_changed',
    'admin_activated', 'job_reminder_sent', 'job_updated', 'job_completed',
    'app_version_updated', 'org_requirement_posted', 'org_requirement_updated',
    'org_requirement_rejected', 'org_requirement_application_decided',
    'otp_setting_updated', 'job_reapplied', 'rate_card_updated', 'scope_of_work_updated'
  ));
