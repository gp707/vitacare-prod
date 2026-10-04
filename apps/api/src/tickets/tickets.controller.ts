import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { TicketsService } from './tickets.service';
import { ForgotPinDto } from './dto/forgot-pin.dto';

/** No JwtAuthGuard — "Forgot PIN" is reachable from any login screen
 *  before the user can authenticate at all. */
@Controller('auth')
export class TicketsController {
  constructor(private readonly ticketsService: TicketsService) {}

  @Post('forgot-pin')
  @HttpCode(HttpStatus.OK)
  forgotPin(@Body() dto: ForgotPinDto, @ClientIp() ip: string | null) {
    return this.ticketsService.createForgotPinTicket(dto, ip);
  }
}
