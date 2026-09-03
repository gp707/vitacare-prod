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
import { IndividualMessagesService } from './individual-messages.service';
import { CreateIndividualMessageDto } from './dto/create-individual-message.dto';
import { UpdateIndividualMessageDto } from './dto/update-individual-message.dto';

@Controller('admin/individual-messages')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminIndividualMessagesController {
  constructor(private readonly individualMessagesService: IndividualMessagesService) {}

  @Get()
  list() {
    return this.individualMessagesService.adminList();
  }

  @Post()
  create(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CreateIndividualMessageDto,
    @ClientIp() ip: string | null,
  ) {
    return this.individualMessagesService.adminCreate(user.sub, dto, ip);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: JwtPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateIndividualMessageDto,
    @ClientIp() ip: string | null,
  ) {
    return this.individualMessagesService.adminUpdate(user.sub, id, dto, ip);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  remove(
    @CurrentUser() user: JwtPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @ClientIp() ip: string | null,
  ) {
    return this.individualMessagesService.adminDelete(user.sub, id, ip);
  }
}
