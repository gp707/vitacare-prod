import { isAllowedForReadOnlyAdmin as allowed, normalizeAdminPath } from './read-only-admin.policy';

const P = '/api/v1';

describe('read-only admin policy', () => {
  it('trims the global prefix and query string', () => {
    expect(normalizeAdminPath(`${P}/admin/jobs/:id?x=1`)).toBe('/admin/jobs/:id');
    expect(normalizeAdminPath('/caregiver/jobs')).toBeNull();
  });

  describe('reads', () => {
    it.each([
      '/admin/dashboard/stats',
      '/admin/caregivers',
      '/admin/caregivers/:id',
      '/admin/jobs',
      '/admin/jobs/:id',
      '/admin/organisation-requirements/:id',
      '/admin/individuals',
      '/admin/organisations/:id',
      '/admin/tickets',
      '/admin/reports/patients/activity',
      '/admin/audit-logs',
      '/admin/error-logs',
      '/admin/insights/summary',
      '/admin/rejections',
    ])('allows GET %s', (path) => {
      expect(allowed('GET', `${P}${path}`)).toBe(true);
    });

    it.each([
      '/admin/rate-card',
      '/admin/scope-of-work',
      '/admin/duty-requirements',
      '/admin/app-versions',
      '/admin/app-maintenance',
      '/admin/otp-settings',
      '/admin/job-settings',
      '/admin/audit-log-retention',
      '/admin/caregiver-messages',
      '/admin/individual-messages',
      '/admin/push-notifications',
    ])('blocks GET %s (settings / messages / push)', (path) => {
      expect(allowed('GET', `${P}${path}`)).toBe(false);
    });
  });

  describe('writes', () => {
    it.each([
      ['POST', '/admin/caregivers/:id/notes'],
      ['POST', '/admin/individuals/:id/notes'],
      ['POST', '/admin/organisations/:id/notes'],
      ['POST', '/admin/jobs/:id/notes'],
      ['POST', '/admin/caregivers/:id/reset-code'],
      ['POST', '/admin/individuals/:id/reset-code'],
      ['POST', '/admin/organisations/:id/reset-code'],
      ['PATCH', '/admin/tickets/:id/resolve'],
      ['PATCH', '/admin/jobs/:id/approve'],
    ])('allows %s %s', (method, path) => {
      expect(allowed(method, `${P}${path}`)).toBe(true);
    });

    it.each([
      ['POST', '/admin/jobs'],
      ['PATCH', '/admin/jobs/:id'],
      ['PATCH', '/admin/jobs/:id/reject'],
      ['PATCH', '/admin/jobs/:id/close'],
      ['PATCH', '/admin/jobs/:id/pending-review'],
      ['POST', '/admin/jobs/:id/remind'],
      ['PATCH', '/admin/jobs/:jobId/applications/:applicationId'],
      ['PATCH', '/admin/organisation-requirements/:id/reject'],
      ['PATCH', '/admin/organisation-requirements/:requirementId/applications/:applicationId'],
      ['PATCH', '/admin/caregivers/:id/status'],
      ['PUT', '/admin/caregivers/:id'],
      ['POST', '/admin/caregivers/:id/selfie'],
      ['DELETE', '/admin/caregivers/:id/documents/history/:versionId'],
      ['PUT', '/admin/individuals/:id'],
      ['PUT', '/admin/organisations/:id'],
      ['PATCH', '/admin/individuals/:id/block'],
      ['PATCH', '/admin/organisations/:id/unblock'],
      ['POST', '/admin/push-notifications'],
      ['PATCH', '/admin/error-logs/:id/resolve'],
      ['PATCH', '/admin/rate-card/:frequency'],
      ['PATCH', '/admin/app-versions/:platform'],
    ])('refuses %s %s', (method, path) => {
      expect(allowed(method, `${P}${path}`)).toBe(false);
    });

    it('allows approving an organisation requirement with an empty PATCH, but not editing one', () => {
      const path = `${P}/admin/organisation-requirements/:id`;
      expect(allowed('PATCH', path, {})).toBe(true);
      expect(allowed('PATCH', path, undefined)).toBe(true);
      expect(allowed('PATCH', path, { number_of_vacancies: 5 })).toBe(false);
    });

    it('refuses anything outside /admin', () => {
      expect(allowed('GET', `${P}/caregiver/jobs`)).toBe(false);
    });
  });
});
