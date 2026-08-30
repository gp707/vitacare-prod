import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { RateCardService } from './rate-card.service';
import { UpdateRateCardDto } from './dto/update-rate-card.dto';

@Controller('admin/rate-card')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminRateCardController {
  constructor(private readonly rateCardService: RateCardService) {}

  @Get()
  get() {
    return this.rateCardService.adminGet();
  }

  @Patch()
  update(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateRateCardDto,
    @ClientIp() ip: string | null,
  ) {
    return this.rateCardService.adminUpdate(user.sub, dto, ip);
  }
}
