import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { DutyRequirementsService } from './duty-requirements.service';
import { UpdateDutyRequirementsDto } from './dto/update-duty-requirements.dto';

@Controller('admin/duty-requirements')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminDutyRequirementsController {
  constructor(private readonly dutyRequirementsService: DutyRequirementsService) {}

  @Get()
  get() {
    return this.dutyRequirementsService.adminGet();
  }

  @Patch()
  update(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateDutyRequirementsDto,
    @ClientIp() ip: string | null,
  ) {
    return this.dutyRequirementsService.adminUpdate(user.sub, dto, ip);
  }
}
