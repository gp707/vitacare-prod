import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { ErrorCatalog } from '@vitacare/shared-constants';
import { AppException } from '../exceptions/app.exception';
import { ErrorLogsRepository } from '../../database/repositories/error-logs.repository';
import { JwtPayload } from '../interfaces/jwt-payload.interface';
import { sanitizeRequestContext } from '../utils/sanitize-request-context';

/**
 * Converts every thrown error into the { success: false, error: { code, message } }
 * envelope. Never leaks raw DB errors or stack traces to the client (CLAUDE.md rules).
 */
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  // Optional — main.ts passes the real repository once the app is
  // bootstrapped (this filter is instantiated before Nest's DI container is
  // usable, so it can't be constructor-injected the normal way). Left
  // undefined in any test that constructs this filter directly, where
  // persisting error rows isn't the point of the test.
  constructor(private readonly errorLogsRepo?: ErrorLogsRepository) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception instanceof AppException) {
      response.status(exception.getStatus()).json({
        success: false,
        error: { code: exception.code, message: exception.message },
      });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();

      // Multer surfaces its own file-size-limit error as a raw 413 HttpException
      // (message "File too large") rather than going through AppException.
      if (status === HttpStatus.PAYLOAD_TOO_LARGE) {
        const entry = ErrorCatalog.UPLOAD_002;
        response.status(entry.status).json({
          success: false,
          error: { code: 'UPLOAD_002', message: entry.message },
        });
        return;
      }

      const body = exception.getResponse();
      const message =
        typeof body === 'string'
          ? body
          : ((body as { message?: string | string[] }).message ?? exception.message);
      const code = status === HttpStatus.NOT_FOUND ? 'GEN_002' : 'GEN_001';
      response.status(status).json({
        success: false,
        error: { code, message: Array.isArray(message) ? message[0] : message },
      });
      return;
    }

    this.logger.error(exception instanceof Error ? exception.stack : exception);
    this.persistErrorLog(exception, ctx.getRequest<Request & { user?: JwtPayload }>());
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      success: false,
      error: { code: 'GEN_003', message: ErrorCatalog.GEN_003.message },
    });
  }

  /** Fire-and-forget — never awaited, and any failure here (e.g. the DB
   *  itself being what's down) is swallowed rather than risking a second
   *  unhandled error inside the error handler. See migration 082's comment
   *  for exactly what does/doesn't land here. */
  private persistErrorLog(exception: unknown, request: Request & { user?: JwtPayload }): void {
    if (!this.errorLogsRepo) return;
    const forwardedFor = request.headers['x-forwarded-for'];
    const ipAddress =
      typeof forwardedFor === 'string' && forwardedFor.length > 0
        ? forwardedFor.split(',')[0].trim()
        : (request.ip ?? null);
    this.errorLogsRepo
      .create({
        method: request.method,
        path: request.originalUrl,
        statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
        message: exception instanceof Error ? exception.message : String(exception),
        stack: exception instanceof Error ? (exception.stack ?? null) : null,
        userId: request.user?.sub ?? null,
        userRole: request.user?.role ?? null,
        ipAddress,
        // What the user was actually doing — sanitized (no PINs/tokens/OTPs,
        // bounded size) — so an admin can see the real data and act on it.
        requestContext: sanitizeRequestContext({ query: request.query, params: request.params, body: request.body }),
        userAgent: this.userAgentOf(request),
      })
      .catch((err) => this.logger.error('Failed to persist error log', err));
  }

  private userAgentOf(request: Request): string | null {
    const header = request.headers['user-agent'];
    return typeof header === 'string' && header.length > 0 ? header.slice(0, 300) : null;
  }
}
