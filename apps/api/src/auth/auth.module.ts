import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { TokenService } from './token.service';
import { LoginThrottleService } from './login-throttle.service';

@Module({
  controllers: [AuthController],
  providers: [AuthService, TokenService, LoginThrottleService],
  exports: [TokenService],
})
export class AuthModule {}
