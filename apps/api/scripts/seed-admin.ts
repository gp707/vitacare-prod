/**
 * Seeds the initial Super Admin user. Run via `npm run seed:admin`.
 * Password is never committed to source control — pass --password or enter it
 * interactively when prompted. See docs/environment-setup.md section 8.
 */
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as readline from 'readline';
import * as bcrypt from 'bcrypt';
import { Client } from 'pg';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const BCRYPT_SALT_ROUNDS = 10;
const DEFAULT_EMAIL = 'vitacasahealthindia@gmail.com';
const DEFAULT_PHONE = '+917259255869';
const DEFAULT_FULL_NAME = 'Super Admin';

function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const value = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
      args[key] = value;
    }
  }
  return args;
}

function promptHidden(question: string): Promise<string> {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const output = (rl as any).output as NodeJS.WritableStream;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (rl as any)._writeToOutput = function _writeToOutput(stringToWrite: string) {
      if (stringToWrite.includes(question)) {
        output.write(stringToWrite);
      } else if (stringToWrite === '\r\n' || stringToWrite === '\n') {
        output.write(stringToWrite);
      } else {
        output.write('*');
      }
    };
    rl.question(question, (answer) => {
      rl.close();
      output.write('\n');
      resolve(answer.trim());
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const email = args.email ?? process.env.ADMIN_NOTIFICATION_EMAIL ?? DEFAULT_EMAIL;
  const phone = args.phone ?? DEFAULT_PHONE;
  const fullName = args.name ?? DEFAULT_FULL_NAME;

  let password = args.password;
  if (!password) {
    password = await promptHidden('Super Admin password: ');
    const confirm = await promptHidden('Confirm password: ');
    if (password !== confirm) {
      console.error('Passwords did not match. Aborting.');
      process.exit(1);
    }
  }

  if (!password || password.length < 6) {
    console.error('Password must be at least 6 characters. Aborting.');
    process.exit(1);
  }

  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('DATABASE_URL is not set (checked apps/api/.env).');
    process.exit(1);
  }

  const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();

  try {
    const existing = await client.query(
      'SELECT id FROM users WHERE email = $1 OR phone = $2',
      [email, phone],
    );
    if (existing.rows.length > 0) {
      console.error(`A user with email "${email}" or phone "${phone}" already exists. Aborting.`);
      process.exit(1);
    }

    const passwordHash = await bcrypt.hash(password, BCRYPT_SALT_ROUNDS);
    const result = await client.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, $4, 'super_admin', true)
       RETURNING id, email, phone, full_name, role`,
      [email, phone, passwordHash, fullName],
    );

    console.log('Super Admin created:');
    console.table(result.rows);
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error('Seed failed:', error instanceof Error ? error.message : error);
  process.exit(1);
});
