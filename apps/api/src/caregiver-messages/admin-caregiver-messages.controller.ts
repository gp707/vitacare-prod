import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Patch,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { CaregiverMessagesService } from './caregiver-messages.service';
import { CreateCaregiverMessageDto } from './dto/create-caregiver-message.dto';
import { UpdateCaregiverMessageDto } from './dto/update-caregiver-message.dto';

@Controller('admin/caregiver-messages')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminCaregiverMessagesController {
  constructor(private readonly caregiverMessagesService: CaregiverMessagesService) {}

  @Get()
  list() {
    return this.caregiverMessagesService.adminList();
  }

  @Post()
  create(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CreateCaregiverMessageDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverMessagesService.adminCreate(user.sub, dto, ip);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: JwtPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCaregiverMessageDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverMessagesService.adminUpdate(user.sub, id, dto, ip);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @CurrentUser() user: JwtPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverMessagesService.adminDelete(user.sub, id, ip);
  }
}
