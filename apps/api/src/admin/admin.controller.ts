import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { UserRole, Validation } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClientIp } from '../common/decorators/client-ip.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AdminService } from './admin.service';
import { ListCaregiversQueryDto } from './dto/list-caregivers-query.dto';
import { UpdateCaregiverStatusDto } from './dto/update-caregiver-status.dto';
import { UpsertAdminNotesDto } from './dto/upsert-admin-notes.dto';
import { ListAuditLogsQueryDto } from './dto/list-audit-logs-query.dto';
import { AdminEditCaregiverDto } from './dto/admin-edit-caregiver.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('dashboard/stats')
  getDashboardStats() {
    return this.adminService.getDashboardStats();
  }

  @Get('caregivers')
  async listCaregivers(@Query() query: ListCaregiversQueryDto) {
    const { data, meta } = await this.adminService.listCaregivers(query);
    return { data, meta };
  }

  @Get('caregivers/:id')
  getCaregiverDetail(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.getCaregiverDetail(id);
  }

  @Patch('caregivers/:id/status')
  @HttpCode(HttpStatus.OK)
  updateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateCaregiverStatusDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminService.updateStatus(id, user.sub, dto, ip);
  }

  @Post('caregivers/:id/notes')
  @HttpCode(HttpStatus.OK)
  upsertNotes(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpsertAdminNotesDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminService.upsertNotes(id, user.sub, dto, ip);
  }

  @Get('audit-logs')
  async listAuditLogs(@Query() query: ListAuditLogsQueryDto) {
    const { data, meta } = await this.adminService.listAuditLogs(query);
    return { data, meta };
  }

  @Put('caregivers/:id')
  @HttpCode(HttpStatus.OK)
  editProfile(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: AdminEditCaregiverDto,
    @ClientIp() ip: string | null,
  ) {
    return this.adminService.editProfile(id, user.sub, dto, ip);
  }

  @Post('caregivers/:id/selfie')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: Validation.FILE_MAX_SIZE_BYTES } }))
  uploadSelfie(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @UploadedFile() file: Express.Multer.File | undefined,
    @ClientIp() ip: string | null,
  ) {
    return this.adminService.uploadSelfie(id, user.sub, file, ip);
  }

  @Post('caregivers/:id/documents')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: Validation.FILE_MAX_SIZE_BYTES } }))
  uploadDocument(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: UploadDocumentDto,
    @UploadedFile() file: Express.Multer.File | undefined,
    @ClientIp() ip: string | null,
  ) {
    return this.adminService.uploadDocument(id, user.sub, dto, file, ip);
  }
}
