import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Put, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminOrganisationsService } from './admin-organisations.service';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { UnblockIndividualDto } from './dto/unblock-individual.dto';
import { ListOrganisationsQueryDto } from './dto/list-organisations-query.dto';
import { AdminEditOrganisationDto } from './dto/admin-edit-organisation.dto';

@Controller('admin/organisations')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminOrganisationsController {
  constructor(private readonly adminOrganisationsService: AdminOrganisationsService) {}

  @Get()
  list(@Query() query: ListOrganisationsQueryDto) {
    return this.adminOrganisationsService.listOrganisations(query);
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.adminOrganisationsService.getOrganisationDetail(id);
  }

  @Put(':id')
  @HttpCode(HttpStatus.OK)
  editProfile(
    @Param('id') id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: AdminEditOrganisationDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminOrganisationsService.editProfile(id, user.sub, dto, ip);
  }

  @Patch(':id/block')
  @HttpCode(HttpStatus.OK)
  block(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: BlockIndividualDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminOrganisationsService.block(id, dto, user.sub, ip);
  }

  @Patch(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblock(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: UnblockIndividualDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminOrganisationsService.unblock(id, dto.level, user.sub, ip);
  }
}
