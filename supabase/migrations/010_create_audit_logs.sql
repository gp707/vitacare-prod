-- ============================================
-- AUDIT LOGS TABLE
-- ============================================
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  target_user_id UUID REFERENCES users(id),
  action VARCHAR(50) NOT NULL CHECK (action IN (
    'registration',
    'login',
    'call_verified',
    'advanced_details_submitted',
    'profile_updated',
    'status_changed',
    'code_changed',
    'service_mode_assigned',
    'admin_edit_profile',
    'admin_note_added',
    'admin_created',
    'admin_deactivated',
    'phone_changed',
    'edits_acknowledged',
    'work_type_assigned',
    'job_posted',
    'job_closed',
    'job_response'
  )),
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID,
  before_value JSONB,
  after_value JSONB,
  ip_address INET,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_target_user_id ON audit_logs(target_user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
