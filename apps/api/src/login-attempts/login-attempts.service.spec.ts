import { LoginAttemptsService } from './login-attempts.service';

describe('LoginAttemptsService', () => {
  const input = {
    phone: '+919876543210',
    userId: null,
    userRole: null,
    app: 'nursenow',
    method: 'code' as const,
    reason: 'wrong_pin',
    ipAddress: '1.2.3.4',
    userAgent: 'Dart/3.6',
  };

  it('writes the attempt through the repository', () => {
    const repo = { create: jest.fn().mockResolvedValue(undefined) };
    new LoginAttemptsService(repo as any).recordFailure(input);
    expect(repo.create).toHaveBeenCalledWith(input);
  });

  it('never throws when the database write rejects — a login must fail for its own reason, not a logging one', async () => {
    const repo = { create: jest.fn().mockRejectedValue(new Error('db down')) };
    const service = new LoginAttemptsService(repo as any);
    expect(() => service.recordFailure(input)).not.toThrow();
    await new Promise((resolve) => setImmediate(resolve)); // no unhandled rejection either
  });

  it('never throws when the repository itself throws synchronously', () => {
    const repo = {
      create: jest.fn(() => {
        throw new Error('boom');
      }),
    };
    expect(() => new LoginAttemptsService(repo as any).recordFailure(input)).not.toThrow();
  });

  it('does not wait for the write — recordFailure returns immediately', () => {
    const repo = { create: jest.fn(() => new Promise(() => undefined)) }; // never resolves
    const result = new LoginAttemptsService(repo as any).recordFailure(input);
    expect(result).toBeUndefined();
  });
});
