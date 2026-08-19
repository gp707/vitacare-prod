import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { OrganisationRequirementsService } from './organisation-requirements.service';
import { ApplyJobDto } from '../jobs/dto/apply-job.dto';

/** A deliberately separate section from GET /caregiver/jobs — organisation
 *  openings are NOT merged into the regular Jobs tab (explicit product
 *  decision, see "NurseNow" in CLAUDE.md). */
@Controller('caregiver/organisation-requirements')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CAREGIVER)
export class CaregiverOrganisationRequirementsController {
  constructor(private readonly requirementsService: OrganisationRequirementsService) {}

  @Get()
  list(@CurrentUser() user: JwtPayload) {
    return this.requirementsService.listActiveForCaregiver(user.sub);
  }

  @Get('assigned')
  getAssigned(@CurrentUser() user: JwtPayload) {
    return this.requirementsService.listMyAssignedRequirements(user.sub);
  }

  @Post(':id/apply')
  @HttpCode(HttpStatus.OK)
  apply(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: ApplyJobDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.applyToRequirement(user.sub, id, dto, ip);
  }

  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  complete(@CurrentUser() user: JwtPayload, @Param('id') id: string, @ClientIp() ip: string | null) {
    return this.requirementsService.completeRequirement(user.sub, id, ip);
  }
}
