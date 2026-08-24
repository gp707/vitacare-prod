import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { OtpService } from './otp.service';
import { SendOtpDto } from './dto/send-otp.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';

/** Public — no auth. A caller doesn't have a session yet at registration,
 *  and login is exactly what this is proving ownership for. */
@Controller('auth/otp')
export class OtpController {
  constructor(private readonly otpService: OtpService) {}

  @Post('send')
  @HttpCode(HttpStatus.OK)
  async send(@Body() dto: SendOtpDto) {
    await this.otpService.send(dto.phone, dto.app, dto.purpose);
    return { sent: true };
  }

  @Post('verify')
  @HttpCode(HttpStatus.OK)
  async verify(@Body() dto: VerifyOtpDto) {
    const phone_verification_token = await this.otpService.verify(dto.phone, dto.app, dto.purpose, dto.otp);
    return { phone_verification_token };
  }
}
