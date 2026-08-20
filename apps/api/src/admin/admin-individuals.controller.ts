import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminIndividualsService } from './admin-individuals.service';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { UnblockIndividualDto } from './dto/unblock-individual.dto';
import { ListIndividualsQueryDto } from './dto/list-individuals-query.dto';

@Controller('admin/individuals')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminIndividualsController {
  constructor(private readonly adminIndividualsService: AdminIndividualsService) {}

  @Get()
  list(@Query() query: ListIndividualsQueryDto) {
    return this.adminIndividualsService.listIndividuals(query);
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.adminIndividualsService.getIndividualDetail(id);
  }

  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  block(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: BlockIndividualDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminIndividualsService.block(id, dto, user.sub, ip);
  }

  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblock(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: UnblockIndividualDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminIndividualsService.unblock(id, dto.level, user.sub, ip);
  }
}
