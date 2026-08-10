#!/usr/bin/env bash
# Applies all .sql files in supabase/migrations/ against $DATABASE_URL, in filename order.
# Tracks applied migrations in a schema_migrations table so re-runs are idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"
ENV_FILE="$SCRIPT_DIR/../apps/api/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is not set (checked apps/api/.env and environment)." >&2
  exit 1
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT NOW()
);
SQL

for file in "$MIGRATIONS_DIR"/*.sql; do
  name="$(basename "$file")"
  already_applied=$(psql "$DATABASE_URL" -t -A -c "SELECT 1 FROM schema_migrations WHERE filename = '$name'")
  if [[ "$already_applied" == "1" ]]; then
    echo "skip:  $name (already applied)"
    continue
  fi
  echo "apply: $name"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$file"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "INSERT INTO schema_migrations (filename) VALUES ('$name')"
done

echo "done."
