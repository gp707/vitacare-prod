import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';

/** Prefers x-forwarded-for (first hop) per SPEC.md section 11.2, falls back to req.ip. */
export const ClientIp = createParamDecorator((_data: unknown, ctx: ExecutionContext): string | null => {
  const request = ctx.switchToHttp().getRequest<Request>();
  const forwardedFor = request.headers['x-forwarded-for'];
  if (typeof forwardedFor === 'string' && forwardedFor.length > 0) {
    return forwardedFor.split(',')[0].trim();
  }
  return request.ip ?? null;
});
