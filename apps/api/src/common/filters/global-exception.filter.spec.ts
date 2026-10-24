import { ArgumentsHost, HttpStatus } from '@nestjs/common';
import { GlobalExceptionFilter } from './global-exception.filter';
import { AppException } from '../exceptions/app.exception';

function makeHost(request: any) {
  const response = {
    status: jest.fn().mockReturnThis(),
    json: jest.fn(),
  };
  const host = {
    switchToHttp: () => ({
      getRequest: () => request,
      getResponse: () => response,
    }),
  } as unknown as ArgumentsHost;
  return { host, response };
}

describe('GlobalExceptionFilter', () => {
  let errorLogsRepo: { create: jest.Mock };
  let filter: GlobalExceptionFilter;

  beforeEach(() => {
    errorLogsRepo = { create: jest.fn().mockResolvedValue(undefined) };
    filter = new GlobalExceptionFilter(errorLogsRepo as any);
  });

  it('never persists an error log for an AppException — those are expected, already-categorized outcomes', () => {
    const { host, response } = makeHost({ method: 'POST', originalUrl: '/v1/auth/login', headers: {} });
    filter.catch(new AppException('AUTH_001'), host);

    expect(response.status).toHaveBeenCalledWith(409);
    expect(errorLogsRepo.create).not.toHaveBeenCalled();
  });

  it('persists a row for a genuinely unhandled exception, with the request method/path/user/ip captured', async () => {
    const request = {
      method: 'POST',
      originalUrl: '/v1/organisation/requirements',
      headers: { 'x-forwarded-for': '203.0.113.5, 10.0.0.1' },
      user: { sub: 'user-1', role: 'organisation' },
      ip: '10.0.0.1',
    };
    const { host, response } = makeHost(request);
    const dbError = new Error('column "duration_type" does not exist');

    filter.catch(dbError, host);
    // create() is fired-and-forgotten inside catch() — flush microtasks.
    await Promise.resolve();
    await Promise.resolve();

    expect(response.status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(response.json).toHaveBeenCalledWith({
      success: false,
      error: { code: 'GEN_003', message: expect.any(String) },
    });
    expect(errorLogsRepo.create).toHaveBeenCalledWith({
      method: 'POST',
      path: '/v1/organisation/requirements',
      statusCode: 500,
      message: 'column "duration_type" does not exist',
      stack: dbError.stack,
      userId: 'user-1',
      userRole: 'organisation',
      ipAddress: '203.0.113.5',
      requestContext: null,
      userAgent: null,
    });
  });

  it('stores the real request data an admin needs to act on, but never secrets, plus the user agent', async () => {
    const request = {
      method: 'POST',
      originalUrl: '/v1/auth/register/individual',
      headers: { 'user-agent': 'Dart/3.6 (dart:io)' },
      query: { source: 'app' },
      params: {},
      body: { phone: '+919876543210', full_name: 'Asha Rao', code: '1234', care_receiver: { age: 74 } },
      ip: '127.0.0.1',
    };
    const { host } = makeHost(request);

    filter.catch(new Error('boom'), host);
    await Promise.resolve();
    await Promise.resolve();

    const input = errorLogsRepo.create.mock.calls[0][0];
    expect(input.userAgent).toBe('Dart/3.6 (dart:io)');
    expect(input.requestContext).toEqual({
      query: { source: 'app' },
      body: { phone: '+919876543210', full_name: 'Asha Rao', code: '[redacted]', care_receiver: { age: 74 } },
    });
    expect(JSON.stringify(input)).not.toContain('1234');
  });

  it('falls back to req.ip when there is no x-forwarded-for header', async () => {
    const request = {
      method: 'GET',
      originalUrl: '/v1/rate-card',
      headers: {},
      ip: '127.0.0.1',
    };
    const { host } = makeHost(request);

    filter.catch(new Error('boom'), host);
    await Promise.resolve();
    await Promise.resolve();

    expect(errorLogsRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ ipAddress: '127.0.0.1', userId: null, userRole: null }),
    );
  });

  it('never throws when no errorLogsRepo was supplied (e.g. a filter constructed directly in a test)', () => {
    const bareFilter = new GlobalExceptionFilter();
    const { host, response } = makeHost({ method: 'GET', originalUrl: '/v1/jobs', headers: {} });

    expect(() => bareFilter.catch(new Error('boom'), host)).not.toThrow();
    expect(response.status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
  });

  it('swallows a failure to persist the error log rather than letting it escape', async () => {
    errorLogsRepo.create.mockRejectedValue(new Error('db is also down'));
    const { host } = makeHost({ method: 'GET', originalUrl: '/v1/jobs', headers: {} });

    expect(() => filter.catch(new Error('boom'), host)).not.toThrow();
    await Promise.resolve();
    await Promise.resolve();
  });
});
