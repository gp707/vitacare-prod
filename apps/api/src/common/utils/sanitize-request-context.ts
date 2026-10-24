/**
 * Builds the sanitized "what was the user doing" snapshot stored with an
 * unexpected-error log (error_logs.request_context, migration 085), so an
 * admin can see the real data behind a failure — the phone number, the
 * form fields, the ids — and reproduce it or call the person.
 *
 * Two non-negotiables:
 *  1. Anything secret-shaped is NEVER stored: PINs/codes, passwords, tokens,
 *     OTPs, authorization, Aadhaar. A key is secret if ANY of its
 *     snake_case / kebab-case / camelCase words is in SECRET_WORDS, so
 *     `code`, `current_code`, `newCode`, `access_token` are all redacted —
 *     but `medical_conditions` / `shipping_area` are not (no false hits from
 *     substring matching).
 *  2. It is bounded: depth, key count, array length, string length and the
 *     total serialized size are all capped, so one huge or hostile request
 *     can't bloat the table.
 *
 * Everything else (phone numbers, names, care needs…) is kept on purpose.
 */
const SECRET_WORDS = new Set([
  'pin',
  'code',
  'password',
  'passcode',
  'token',
  'secret',
  'authorization',
  'otp',
  'aadhaar',
  'cvv',
  'signature',
]);

const REDACTED = '[redacted]';
const MAX_DEPTH = 4;
const MAX_KEYS = 40;
const MAX_ARRAY_ITEMS = 20;
const MAX_STRING_LENGTH = 300;
export const MAX_CONTEXT_JSON_LENGTH = 8000;

export function isSecretKey(key: string): boolean {
  const words = key
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
  return words.some((word) => SECRET_WORDS.has(word));
}

function sanitizeValue(value: unknown, depth: number): unknown {
  if (value === null || value === undefined) return value ?? null;
  if (typeof value === 'boolean' || typeof value === 'number') return value;
  if (typeof value === 'string') {
    return value.length > MAX_STRING_LENGTH
      ? `${value.slice(0, MAX_STRING_LENGTH)}…[+${value.length - MAX_STRING_LENGTH} chars]`
      : value;
  }
  if (depth >= MAX_DEPTH) return '[truncated]';
  if (Array.isArray(value)) {
    const items = value.slice(0, MAX_ARRAY_ITEMS).map((item) => sanitizeValue(item, depth + 1));
    if (value.length > MAX_ARRAY_ITEMS) items.push(`[+${value.length - MAX_ARRAY_ITEMS} more]`);
    return items;
  }
  if (typeof value === 'object') {
    if (Buffer.isBuffer(value)) return '[binary]';
    const out: Record<string, unknown> = {};
    const entries = Object.entries(value as Record<string, unknown>);
    for (const [key, inner] of entries.slice(0, MAX_KEYS)) {
      out[key] = isSecretKey(key) ? REDACTED : sanitizeValue(inner, depth + 1);
    }
    if (entries.length > MAX_KEYS) out['[truncated]'] = `+${entries.length - MAX_KEYS} more keys`;
    return out;
  }
  return '[unsupported]';
}

function isEmpty(value: unknown): boolean {
  return (
    value === undefined ||
    value === null ||
    (typeof value === 'object' && Object.keys(value as object).length === 0)
  );
}

/** Returns null when there is nothing worth storing. */
export function sanitizeRequestContext(request: {
  query?: unknown;
  params?: unknown;
  body?: unknown;
}): Record<string, unknown> | null {
  const context: Record<string, unknown> = {};
  if (!isEmpty(request.query)) context.query = sanitizeValue(request.query, 0);
  if (!isEmpty(request.params)) context.params = sanitizeValue(request.params, 0);
  if (!isEmpty(request.body)) context.body = sanitizeValue(request.body, 0);
  if (Object.keys(context).length === 0) return null;

  const json = JSON.stringify(context);
  if (json.length > MAX_CONTEXT_JSON_LENGTH) {
    return { truncated: true, preview: `${json.slice(0, 2000)}…` };
  }
  return context;
}
