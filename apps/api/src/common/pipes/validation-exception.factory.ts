import { ValidationError } from 'class-validator';
import { ErrorCatalog } from '@vitacare/shared-constants';
import { AppException } from '../exceptions/app.exception';

/**
 * DTO field decorators set their `message` to an ErrorCatalog code (e.g. 'PROFILE_007')
 * instead of free text, so a failed validation can be resolved back to the exact
 * catalog entry (status + message) documented in SPEC.md section 7.
 */
function firstCode(errors: ValidationError[]): string | undefined {
  for (const error of errors) {
    if (error.constraints) {
      const candidate = Object.values(error.constraints)[0];
      if (candidate && candidate in ErrorCatalog) return candidate;
    }
    if (error.children?.length) {
      const nested = firstCode(error.children);
      if (nested) return nested;
    }
  }
  return undefined;
}

export function validationExceptionFactory(errors: ValidationError[]): AppException {
  return new AppException(firstCode(errors) ?? 'GEN_001');
}
