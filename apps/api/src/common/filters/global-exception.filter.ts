import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Response } from 'express';
import { ErrorCatalog } from '@vitacare/shared-constants';
import { AppException } from '../exceptions/app.exception';

/**
 * Converts every thrown error into the { success: false, error: { code, message } }
 * envelope. Never leaks raw DB errors or stack traces to the client (CLAUDE.md rules).
 */
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

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
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      success: false,
      error: { code: 'GEN_003', message: ErrorCatalog.GEN_003.message },
    });
  }
}
