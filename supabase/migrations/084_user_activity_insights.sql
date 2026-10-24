-- Admin "Insights" screen: who is actually using the app, and which buttons
-- they use. Two additions, both purely additive (old backend code ignores
-- them, so this can be applied before the backend deploy).
--
-- 1. users.last_seen_at — bumped (throttled, ~every 5 min per user) by
--    JwtAuthGuard on any authenticated request. Needed because
--    caregiver/individual/organisation tokens never expire: a user who
--    logged in once months ago and uses the app daily never produces
--    another `login` audit row, so audit_logs alone can't answer "who was
--    active in the last 24h".
--
--    Backfilled from the audit trail (their latest audited action), and
--    falling back to created_at (registering counts as first activity) for
--    anyone with no audit rows — so the "registered but never used the app"
--    report is meaningful from day one instead of flagging every existing
--    account. Accounts that use the app without ever triggering an audited
--    action will look idle until their next request after this ships.
--
-- 2. app_events — one row per tracked screen view or button tap, sent in
--    small batches by the JustHeal app (POST /events). user_id is nullable
--    so pre-login screens (login/registration) can be tracked too.
--    ON DELETE CASCADE (not SET NULL): an event with no user is useless for
--    "most used by role" and we never want orphaned usage rows to outlive
--    the account they describe. Rows older than 90 days are purged daily by
--    InsightsService.

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

UPDATE users u
   SET last_seen_at = a.last_action
  FROM (
    SELECT user_id, MAX(created_at) AS last_action
      FROM audit_logs
     WHERE user_id IS NOT NULL
     GROUP BY user_id
  ) a
 WHERE a.user_id = u.id
   AND u.last_seen_at IS NULL;

UPDATE users
   SET last_seen_at = created_at
 WHERE last_seen_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_last_seen_at ON users(last_seen_at);

CREATE TABLE IF NOT EXISTS app_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  user_role VARCHAR(20),
  kind VARCHAR(10) NOT NULL CHECK (kind IN ('screen', 'tap')),
  flow VARCHAR(40) NOT NULL,
  screen VARCHAR(60) NOT NULL,
  action VARCHAR(60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_events_created_at ON app_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_usage
  ON app_events(kind, flow, screen, action, created_at);
CREATE INDEX IF NOT EXISTS idx_app_events_user_id ON app_events(user_id);
