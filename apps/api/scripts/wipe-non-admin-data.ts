/**
 * Wipes every caregiver/individual/organisation account and everything
 * derived from it (profiles, jobs, care receivers, applications, tokens,
 * OTP records, audit logs) plus their uploaded documents in Supabase
 * Storage. Admin/super_admin accounts and their refresh tokens, and every
 * platform-wide settings table (rate_card, scope_of_work,
 * duty_requirements, app_min_versions, job_settings, otp_auth_settings),
 * are left untouched.
 *
 * Every table listed here can only ever hold caregiver/individual/
 * organisation data (their profile_id/posted_by chain always terminates
 * at a non-admin user — see the INSERT statements in
 * src/database/repositories/*.repository.ts), so each gets a wholesale
 * DELETE. The two exceptions are `refresh_tokens` and `users` themselves,
 * which can hold admin rows too and are explicitly scoped by role.
 *
 * IRREVERSIBLE. Runs against whatever DATABASE_URL/SUPABASE_URL point to
 * in apps/api/.env — currently the live production database.
 *
 * Dry run (default): npx ts-node scripts/wipe-non-admin-data.ts
 * Actually delete:    npx ts-node scripts/wipe-non-admin-data.ts --confirm
 */
import * as dotenv from 'dotenv';
import * as path from 'path';
import { Client } from 'pg';
import { createClient } from '@supabase/supabase-js';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const STORAGE_BUCKET = 'caregiver-documents';

const NON_ADMIN_USERS_SQL = `SELECT id FROM users WHERE role NOT IN ('admin', 'super_admin')`;

// Deletion order matters — children before parents, respecting every FK in
// the schema.
const DELETE_STATEMENTS: { table: string; sql: string }[] = [
  { table: 'job_applications', sql: `DELETE FROM job_applications` },
  { table: 'organisation_requirement_applications', sql: `DELETE FROM organisation_requirement_applications` },
  { table: 'caregiver_languages', sql: `DELETE FROM caregiver_languages` },
  { table: 'caregiver_preferred_cities', sql: `DELETE FROM caregiver_preferred_cities` },
  { table: 'admin_notes', sql: `DELETE FROM admin_notes` },
  { table: 'jobs', sql: `DELETE FROM jobs` },
  { table: 'care_receivers', sql: `DELETE FROM care_receivers` },
  { table: 'organisation_requirements', sql: `DELETE FROM organisation_requirements` },
  { table: 'caregiver_profiles', sql: `DELETE FROM caregiver_profiles` },
  { table: 'individual_profiles', sql: `DELETE FROM individual_profiles` },
  { table: 'organisation_profiles', sql: `DELETE FROM organisation_profiles` },
  { table: 'refresh_tokens', sql: `DELETE FROM refresh_tokens WHERE user_id IN (${NON_ADMIN_USERS_SQL})` },
  { table: 'audit_logs', sql: `DELETE FROM audit_logs` }, // old dev-era activity log, not admin credentials
  { table: 'otp_verifications', sql: `DELETE FROM otp_verifications` }, // phone-keyed, all transient anyway
  { table: 'users', sql: `DELETE FROM users WHERE role NOT IN ('admin', 'super_admin')` },
];

async function dryRun(client: Client) {
  console.log('DRY RUN — nothing will be deleted. Pass --confirm to actually run this.\n');
  for (const { table, sql } of DELETE_STATEMENTS) {
    const countSql = `SELECT COUNT(*) FROM (${sql.replace(/^DELETE FROM/, 'SELECT * FROM')}) t`;
    const result = await client.query(countSql);
    console.log(`  ${table.padEnd(36)} would delete ${result.rows[0].count} row(s)`);
  }
  const admins = await client.query(`SELECT phone, email, role FROM users WHERE role IN ('admin', 'super_admin')`);
  console.log(`\n${admins.rows.length} admin/super_admin account(s) will be kept:`);
  console.table(admins.rows);
}

async function wipeDatabase(client: Client) {
  await client.query('BEGIN');
  try {
    for (const { table, sql } of DELETE_STATEMENTS) {
      const result = await client.query(sql);
      console.log(`  ${table.padEnd(36)} deleted ${result.rowCount} row(s)`);
    }
    await client.query('COMMIT');
    console.log('\nDatabase wipe committed.');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error during wipe — rolled back, nothing was deleted:', error);
    throw error;
  }
}

async function wipeStorage() {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    console.error('SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY not set — skipping storage cleanup.');
    return;
  }
  const supabase = createClient(url, serviceKey);

  const { data: folders, error: listError } = await supabase.storage.from(STORAGE_BUCKET).list();
  if (listError) {
    console.error('Could not list storage bucket:', listError.message);
    return;
  }
  if (!folders || folders.length === 0) {
    console.log('Storage bucket already empty.');
    return;
  }

  let totalDeleted = 0;
  for (const folder of folders) {
    const { data: files, error: subListError } = await supabase.storage.from(STORAGE_BUCKET).list(folder.name);
    if (subListError || !files) continue;
    const paths = files.map((f) => `${folder.name}/${f.name}`);
    if (paths.length === 0) continue;
    const { error: removeError } = await supabase.storage.from(STORAGE_BUCKET).remove(paths);
    if (removeError) {
      console.error(`  Failed to delete ${folder.name}/:`, removeError.message);
      continue;
    }
    totalDeleted += paths.length;
  }
  console.log(`Storage: deleted ${totalDeleted} file(s) across ${folders.length} folder(s) from "${STORAGE_BUCKET}".`);
}

async function main() {
  const confirm = process.argv.includes('--confirm');
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('DATABASE_URL is not set (checked apps/api/.env).');
    process.exit(1);
  }

  const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();

  try {
    if (!confirm) {
      await dryRun(client);
      return;
    }
    console.log('Wiping database (transactional)...\n');
    await wipeDatabase(client);
    console.log('\nWiping Supabase Storage...\n');
    await wipeStorage();
    console.log('\nDone.');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error('Wipe failed:', error instanceof Error ? error.message : error);
  process.exit(1);
});
