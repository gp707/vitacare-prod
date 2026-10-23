-- One row per calendar day (UTC), upserted on every request by a thin
-- middleware — lets admin-web show "N requests, M errors" without having
-- to COUNT(*) a row-per-request table (which error_logs deliberately is
-- NOT — see migration 082's comment). total_errors counts every response
-- with status >= 500, independent of (and a cheap cross-check against)
-- error_logs' own row count once that table starts rolling off after 7
-- days (migration adds the retention cron in code, not SQL).
CREATE TABLE request_stats (
  date DATE PRIMARY KEY,
  total_requests BIGINT NOT NULL DEFAULT 0,
  total_errors BIGINT NOT NULL DEFAULT 0
);
