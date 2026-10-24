import { Global, Module } from '@nestjs/common';
import { LoginAttemptsService } from './login-attempts.service';

/** Global so AuthService and OtpService (two unrelated modules) can both
 *  record failures without importing each other. */
@Global()
@Module({
  providers: [LoginAttemptsService],
  exports: [LoginAttemptsService],
})
export class LoginAttemptsModule {}
