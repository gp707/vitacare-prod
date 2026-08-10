import { HttpException } from '@nestjs/common';
import { ErrorCatalog, ErrorCode } from '@vitacare/shared-constants';

/**
 * Throw with a catalog error code; status and message are resolved from
 * ErrorCatalog (packages/shared-constants) so API responses always match
 * the documented error catalog in SPEC.md section 7.
 */
export class AppException extends HttpException {
  public readonly code: string;

  constructor(code: ErrorCode | string, messageOverride?: string) {
    const entry = ErrorCatalog[code as ErrorCode] ?? ErrorCatalog.GEN_003;
    const resolvedCode = ErrorCatalog[code as ErrorCode] ? code : 'GEN_003';
    super(messageOverride ?? entry.message, entry.status);
    this.code = resolvedCode as string;
  }
}
