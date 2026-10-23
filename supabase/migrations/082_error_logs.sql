-- Minimal backend error-logging: every genuinely unexpected server error
-- (the GlobalExceptionFilter's catch-all branch — anything that isn't an
-- AppException or a regular HttpException, i.e. not an already-categorized
-- business error) is now persisted here instead of only ever appearing in
-- whatever process log happens to be watched at the time. Deliberately does
-- NOT capture ordinary 4xx validation/business errors (AUTH_001, GEN_001,
-- etc.) — those are expected, already-coded outcomes, not the "something
-- broke" signal this table exists for. user_id is nullable since most
-- requests that crash the server are from an unauthenticated route or one
-- where auth hadn't resolved yet; set null on user deletion rather than
-- blocking it, same precedent as support_tickets.resolved_by.
CREATE TABLE error_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method VARCHAR(10) NOT NULL,
  path TEXT NOT NULL,
  status_code INT NOT NULL,
  message TEXT NOT NULL,
  stack TEXT,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  user_role VARCHAR(20),
  ip_address VARCHAR(45),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_error_logs_created_at ON error_logs(created_at DESC);
