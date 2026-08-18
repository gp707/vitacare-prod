import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { RegisterIndividualDto } from './dto/register-individual.dto';
import { LoginCodeDto } from './dto/login-code.dto';
import { LoginEmailDto } from './dto/login-email.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  register(@Body() dto: RegisterDto, @ClientIp() ip: string | null) {
    return this.authService.register(dto, ip);
  }

  @Post('register/individual')
  @HttpCode(HttpStatus.CREATED)
  registerIndividual(@Body() dto: RegisterIndividualDto, @ClientIp() ip: string | null) {
    return this.authService.registerIndividual(dto, ip);
  }

  @Post('login/code')
  @HttpCode(HttpStatus.OK)
  loginCode(@Body() dto: LoginCodeDto, @ClientIp() ip: string | null) {
    return this.authService.loginCode(dto, ip);
  }

  @Post('login/email')
  @HttpCode(HttpStatus.OK)
  loginEmail(@Body() dto: LoginEmailDto, @ClientIp() ip: string | null) {
    return this.authService.loginEmail(dto, ip);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto.refresh_token);
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  async logout(@CurrentUser() user: JwtPayload) {
    await this.authService.logout(user.sub);
    return { message: 'Logged out successfully' };
  }
}
