import { AuditService } from './audit.service';

describe('AuditService', () => {
  let service: AuditService;
  let db: any;

  beforeEach(() => {
    db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
    service = new AuditService(db);
  });

  it('inserts a row with JSON-encoded before/after values', async () => {
    await service.log({
      userId: 'user-1',
      targetUserId: 'user-2',
      action: 'status_changed' as any,
      entityType: 'caregiver_profiles',
      entityId: 'profile-1',
      beforeValue: { verification_status: 'pending_verification' },
      afterValue: { verification_status: 'available' },
      ipAddress: '203.0.113.5',
    });

    expect(db.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        'user-1',
        'user-2',
        'status_changed',
        'caregiver_profiles',
        'profile-1',
        JSON.stringify({ verification_status: 'pending_verification' }),
        JSON.stringify({ verification_status: 'available' }),
        '203.0.113.5',
      ],
    );
  });

  it('defaults optional fields to null', async () => {
    await service.log({
      userId: 'user-1',
      action: 'login' as any,
      entityType: 'users',
    });

    expect(db.query).toHaveBeenCalledWith(expect.any(String), [
      'user-1',
      null,
      'login',
      'users',
      null,
      null,
      null,
      null,
    ]);
  });

  it('swallows write failures so a broken audit insert never throws', async () => {
    db.query.mockRejectedValueOnce(new Error('DB down'));
    await expect(
      service.log({ userId: 'user-1', action: 'login' as any, entityType: 'users' }),
    ).resolves.toBeUndefined();
  });
});
