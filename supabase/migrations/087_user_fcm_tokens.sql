-- One push token per physical device, not one per account.
--
-- users.fcm_token held a single token per user, so (a) a person with two
-- devices only ever got pushes on whichever registered last, and (b) the
-- server could not forget a device on logout, so a phone handed to a
-- different account kept receiving the previous account's pushes. Tokens now
-- live here, keyed by the token itself: a token belongs to exactly one account
-- at a time (registering it for another account moves it), and an account can
-- hold many.
--
-- users.fcm_token is intentionally KEPT and still dual-written by the API, so
-- the previous backend release can be rolled back without losing push. A
-- later migration drops it once that is no longer needed.
--
-- ON DELETE CASCADE: tokens are operational data and go with the account.
-- Idempotent on purpose: safe to re-run after the backend deploys to pick up
-- tokens the previous release wrote to users.fcm_token in the meantime.

CREATE TABLE IF NOT EXISTS user_fcm_tokens (
  token TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);

INSERT INTO user_fcm_tokens (token, user_id)
SELECT fcm_token, id FROM users
WHERE fcm_token IS NOT NULL AND deleted_at IS NULL
ON CONFLICT (token) DO NOTHING;
