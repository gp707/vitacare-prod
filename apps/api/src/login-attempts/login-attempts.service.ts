import { Injectable, Logger } from '@nestjs/common';
import { LoginAttemptsRepository, CreateLoginAttemptInput } from '../database/repositories/login-attempts.repository';

/** Records failed logins for the admin "Login problems" report. Telemetry
 *  must never be able to break (or even slow) a login: the write is
 *  fire-and-forget and every failure is swallowed — a login that fails for
 *  the user's own reason must still fail with *that* error, not a logging one. */
@Injectable()
export class LoginAttemptsService {
  private readonly logger = new Logger(LoginAttemptsService.name);

  constructor(private readonly loginAttemptsRepo: LoginAttemptsRepository) {}

  recordFailure(input: CreateLoginAttemptInput): void {
    try {
      void Promise.resolve(this.loginAttemptsRepo.create(input)).catch((err) =>
        this.logger.warn(`Failed to record login attempt: ${err instanceof Error ? err.message : String(err)}`),
      );
    } catch (err) {
      this.logger.warn(`Failed to record login attempt: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
}
