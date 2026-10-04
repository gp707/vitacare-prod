import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminPushNotificationsService } from './admin-push-notifications.service';
import { CreatePushNotificationDto } from './dto/create-push-notification.dto';
import { ListPushNotificationsQueryDto } from './dto/list-push-notifications-query.dto';

@Controller('admin/push-notifications')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminPushNotificationsController {
  constructor(private readonly service: AdminPushNotificationsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() user: JwtPayload, @Body() dto: CreatePushNotificationDto, @ClientIp() ip: string | null) {
    return this.service.create(user.sub, dto, ip);
  }

  @Get()
  list(@Query() query: ListPushNotificationsQueryDto) {
    return this.service.list(query);
  }

  @Patch(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(@CurrentUser() user: JwtPayload, @Param('id') id: string, @ClientIp() ip: string | null) {
    return this.service.cancel(id, user.sub, ip);
  }
}
