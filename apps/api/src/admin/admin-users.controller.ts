import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Patch, Post, Put, UseGuards } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminUsersService } from './admin-users.service';
import { CreateAdminDto } from './dto/create-admin.dto';
import { UpdateAdminDto } from './dto/update-admin.dto';
import { UpdateAdminRoleDto } from './dto/update-admin-role.dto';

@Controller('admin/users')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.SUPER_ADMIN)
export class AdminUsersController {
  constructor(private readonly adminUsersService: AdminUsersService) {}

  @Get()
  listAdmins() {
    return this.adminUsersService.listAdmins();
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  createAdmin(@Body() dto: CreateAdminDto, @CurrentUser() user: JwtPayload, @ClientIp() ip: string | null) {
    return this.adminUsersService.createAdmin(dto, user.sub, ip);
  }

  @Put(':id')
  @HttpCode(HttpStatus.OK)
  updateAdmin(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateAdminDto) {
    return this.adminUsersService.updateAdmin(id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  deactivateAdmin(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @ClientIp() ip: string | null,
  ) {
    return this.adminUsersService.deactivateAdmin(id, user.sub, ip);
  }

  @Patch(':id/activate')
  @HttpCode(HttpStatus.OK)
  activateAdmin(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @ClientIp() ip: string | null,
  ) {
    return this.adminUsersService.activateAdmin(id, user.sub, ip);
  }

  @Patch(':id/role')
  @HttpCode(HttpStatus.OK)
  updateAdminRole(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAdminRoleDto,
    @CurrentUser() user: JwtPayload,
    @ClientIp() ip: string | null,
  ) {
    return this.adminUsersService.updateAdminRole(id, dto, user.sub, ip);
  }
}
