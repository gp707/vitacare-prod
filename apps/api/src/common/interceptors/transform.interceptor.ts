import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

interface SuccessEnvelope<T> {
  success: true;
  data: T;
  meta?: unknown;
}

/**
 * Wraps every controller return value in the { success: true, data } envelope
 * required by CLAUDE.md / SPEC.md 6.2. Controllers may return { data, meta } to
 * populate pagination meta; anything else is treated as the data payload directly.
 */
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, SuccessEnvelope<T>> {
  intercept(context: ExecutionContext, next: CallHandler<T>): Observable<SuccessEnvelope<T>> {
    return next.handle().pipe(
      map((result: unknown) => {
        if (
          result &&
          typeof result === 'object' &&
          'data' in result &&
          'meta' in (result as Record<string, unknown>)
        ) {
          const { data, meta } = result as { data: T; meta: unknown };
          return { success: true, data, meta };
        }
        return { success: true, data: result as T };
      }),
    );
  }
}
