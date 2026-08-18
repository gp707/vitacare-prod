import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { IndividualService } from './individual.service';
import { CreateIndividualRequirementDto } from './dto/create-individual-requirement.dto';
import { DecideApplicationDto } from '../jobs/dto/decide-application.dto';

@Controller('individual')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.INDIVIDUAL)
export class IndividualController {
  constructor(private readonly individualService: IndividualService) {}

  @Get('me')
  getMe(@CurrentUser() user: JwtPayload) {
    return this.individualService.getMe(user.sub);
  }

  @Post('requirements')
  @HttpCode(HttpStatus.CREATED)
  createRequirement(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CreateIndividualRequirementDto,
    @ClientIp() ip: string | null,
  ) {
    return this.individualService.createRequirement(user.sub, dto, ip);
  }

  @Get('requirements')
  listRequirements(@CurrentUser() user: JwtPayload) {
    return this.individualService.listMyRequirements(user.sub);
  }

  @Get('requirements/:id/applications')
  listApplications(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.individualService.getMyRequirementApplications(user.sub, id);
  }

  @Patch('requirements/:jobId/applications/:applicationId')
  @HttpCode(HttpStatus.OK)
  decideApplication(
    @CurrentUser() user: JwtPayload,
    @Param('jobId') jobId: string,
    @Param('applicationId') applicationId: string,
    @Body() dto: DecideApplicationDto,
    @ClientIp() ip: string | null,
  ) {
    return this.individualService.decideMyApplication(user.sub, jobId, applicationId, dto, ip);
  }
}
