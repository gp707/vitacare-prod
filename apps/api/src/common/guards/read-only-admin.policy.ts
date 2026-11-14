/**
 * What a `read_only_admin` may do on the admin API. Applied by RolesGuard to
 * that role only — `admin` and `super_admin` never go through it.
 *
 * Default: every admin GET is allowed, except the settings/messages/push
 * areas below. Every write is refused unless it is on the short allow-list.
 * Paths are Express route patterns (`:id`, not real ids), from `/admin` on.
 */

/** GETs this role may not read (settings, messages, push). */
const BLOCKED_READ_PREFIXES = [
  '/admin/app-maintenance',
  '/admin/app-versions',
  '/admin/audit-log-retention',
  '/admin/caregiver-messages',
  '/admin/individual-messages',
  '/admin/duty-requirements',
  '/admin/job-settings',
  '/admin/otp-settings',
  '/admin/rate-card',
  '/admin/scope-of-work',
  '/admin/push-notifications',
];

/** The only writes allowed: internal notes, PIN reset, resolve tickets, approve jobs. */
const ALLOWED_WRITES: ReadonlyArray<{ method: string; pattern: RegExp }> = [
  // Internal notes
  { method: 'POST', pattern: /^\/admin\/caregivers\/:id\/notes$/ },
  { method: 'POST', pattern: /^\/admin\/individuals\/:id\/notes$/ },
  { method: 'POST', pattern: /^\/admin\/organisations\/:id\/notes$/ },
  { method: 'POST', pattern: /^\/admin\/jobs\/:id\/notes$/ },
  // PIN reset
  { method: 'POST', pattern: /^\/admin\/caregivers\/:id\/reset-code$/ },
  { method: 'POST', pattern: /^\/admin\/individuals\/:id\/reset-code$/ },
  { method: 'POST', pattern: /^\/admin\/organisations\/:id\/reset-code$/ },
  // Tickets
  { method: 'PATCH', pattern: /^\/admin\/tickets\/:id\/resolve$/ },
  // Approve a pending job
  { method: 'PATCH', pattern: /^\/admin\/jobs\/:id\/approve$/ },
];

const ORG_REQUIREMENT_PATCH = /^\/admin\/organisation-requirements\/:id$/;
const CAREGIVER_STATUS_PATCH = /^\/admin\/caregivers\/:id\/status$/;

/** Trims a route pattern/path to start at `/admin` and drops any query string. */
export function normalizeAdminPath(routePath: string): string | null {
  const noQuery = routePath.split('?')[0];
  const at = noQuery.indexOf('/admin');
  if (at < 0) return null;
  const path = noQuery.slice(at);
  return path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;
}

function isEmptyBody(body: unknown): boolean {
  if (body === undefined || body === null) return true;
  return typeof body === 'object' && !Array.isArray(body) && Object.keys(body as object).length === 0;
}

export function isAllowedForReadOnlyAdmin(method: string, routePath: string, body?: unknown): boolean {
  const path = normalizeAdminPath(routePath);
  if (!path) return false;
  const m = method.toUpperCase();

  if (m === 'GET' || m === 'HEAD') {
    return !BLOCKED_READ_PREFIXES.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
  }

  if (ALLOWED_WRITES.some((rule) => rule.method === m && rule.pattern.test(path))) return true;

  // Approving a caregiver is the one status change allowed: the request must ask
  // for `available` (the service additionally requires the caregiver to be in
  // `pending_call`, so this can never unassign, assign or reject anyone).
  if (m === 'PATCH' && CAREGIVER_STATUS_PATCH.test(path)) {
    const status = typeof body === 'object' && body !== null ? (body as { status?: unknown }).status : undefined;
    return status === 'available';
  }

  // An organisation requirement is approved by a bare PATCH with no fields
  // (see CLAUDE.md "Admin's own edit mirrors…"); a PATCH that carries any
  // field is an edit and stays refused.
  return m === 'PATCH' && ORG_REQUIREMENT_PATCH.test(path) && isEmptyBody(body);
}
