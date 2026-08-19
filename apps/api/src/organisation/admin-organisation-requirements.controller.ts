import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { OrganisationRequirementsService } from './organisation-requirements.service';
import { UpdateOrganisationRequirementDto } from './dto/update-organisation-requirement.dto';
import { ListOrganisationRequirementsQueryDto } from './dto/list-organisation-requirements-query.dto';
import { RejectJobDto } from '../jobs/dto/reject-job.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';

@Controller('admin/organisation-requirements')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminOrganisationRequirementsController {
  constructor(private readonly requirementsService: OrganisationRequirementsService) {}

  @Get()
  list(@Query() query: ListOrganisationRequirementsQueryDto) {
    return this.requirementsService.listRequirementsForAdmin(query);
  }

  @Get(':id')
  getDetail(@Param('id') id: string) {
    return this.requirementsService.getRequirementDetailForAdmin(id);
  }

  @Patch(':id')
  @HttpCode(HttpStatus.OK)
  update(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: UpdateOrganisationRequirementDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.updateRequirement(user.sub, id, dto, ip);
  }

  @Patch(':id/reject')
  @HttpCode(HttpStatus.OK)
  reject(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: RejectJobDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.rejectRequirement(user.sub, id, dto.reason, ip);
  }

  @Patch(':requirementId/applications/:applicationId')
  @HttpCode(HttpStatus.OK)
  decideApplication(
    @CurrentUser() user: JwtPayload,
    @Param('requirementId') requirementId: string,
    @Param('applicationId') applicationId: string,
    @Body() dto: DecideApplicationDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.decideApplication(user.sub, requirementId, applicationId, dto, ip);
  }
}
