import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { OrganisationService } from './organisation.service';
import { OrganisationRequirementsService } from './organisation-requirements.service';
import { CreateOrganisationRequirementDto } from './dto/create-organisation-requirement.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';

@Controller('organisation')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ORGANISATION)
export class OrganisationController {
  constructor(
    private readonly organisationService: OrganisationService,
    private readonly requirementsService: OrganisationRequirementsService,
  ) {}

  @Get('me')
  getMe(@CurrentUser() user: JwtPayload) {
    return this.organisationService.getMe(user.sub);
  }

  @Post('requirements')
  @HttpCode(HttpStatus.CREATED)
  createRequirement(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CreateOrganisationRequirementDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.createRequirement(user.sub, dto, ip);
  }

  @Get('requirements')
  listRequirements(@CurrentUser() user: JwtPayload) {
    return this.requirementsService.listMyRequirements(user.sub);
  }

  @Get('requirements/:id/applications')
  listApplications(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.requirementsService.getRequirementApplications(user.sub, id);
  }

  @Patch('requirements/:requirementId/applications/:applicationId')
  @HttpCode(HttpStatus.OK)
  decideApplication(
    @CurrentUser() user: JwtPayload,
    @Param('requirementId') requirementId: string,
    @Param('applicationId') applicationId: string,
    @Body() dto: DecideApplicationDto,
    @ClientIp() ip: string | null,
  ) {
    return this.requirementsService.decideMyApplication(user.sub, requirementId, applicationId, dto, ip);
  }

  @Patch('profile/phone')
  @HttpCode(HttpStatus.OK)
  updatePhone(@CurrentUser() user: JwtPayload, @Body() dto: UpdatePhoneDto, @ClientIp() ip: string | null) {
    return this.organisationService.updatePhone(user.sub, dto, ip);
  }

  @Patch('profile/code')
  @HttpCode(HttpStatus.OK)
  updateCode(@CurrentUser() user: JwtPayload, @Body() dto: UpdateCodeDto, @ClientIp() ip: string | null) {
    return this.organisationService.updateCode(user.sub, dto, ip);
  }
}
