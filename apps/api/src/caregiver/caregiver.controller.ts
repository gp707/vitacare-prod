import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Patch,
  Put,
  Post,
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
import { CaregiverService } from './caregiver.service';
import { UpdateBasicProfileDto } from './dto/update-basic-profile.dto';
import { SubmitAdvancedDetailsDto } from './dto/submit-advanced-details.dto';
import { EditAdvancedProfileDto } from './dto/edit-advanced-profile.dto';
import { UpdatePhoneDto } from './dto/update-phone.dto';
import { UpdateCodeDto } from './dto/update-code.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { UpdateFcmTokenDto } from './dto/update-fcm-token.dto';

@Controller('caregiver')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CAREGIVER)
export class CaregiverController {
  constructor(private readonly caregiverService: CaregiverService) {}

  @Get('profile')
  getProfile(@CurrentUser() user: JwtPayload) {
    return this.caregiverService.getProfile(user.sub);
  }

  @Put('profile/basic')
  @HttpCode(HttpStatus.OK)
  updateBasicProfile(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateBasicProfileDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverService.updateBasicProfile(user.sub, dto, ip);
  }

  @Put('profile/advanced')
  @HttpCode(HttpStatus.OK)
  submitAdvancedDetails(
    @CurrentUser() user: JwtPayload,
    @Body() dto: SubmitAdvancedDetailsDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverService.submitAdvancedDetails(user.sub, dto, ip);
  }

  @Patch('profile/advanced')
  @HttpCode(HttpStatus.OK)
  editAdvancedProfile(
    @CurrentUser() user: JwtPayload,
    @Body() dto: EditAdvancedProfileDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverService.editAdvancedProfile(user.sub, dto, ip);
  }

  @Patch('profile/phone')
  @HttpCode(HttpStatus.OK)
  updatePhone(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdatePhoneDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverService.updatePhone(user.sub, dto, ip);
  }

  @Patch('profile/code')
  @HttpCode(HttpStatus.OK)
  updateCode(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateCodeDto,
    @ClientIp() ip: string | null,
  ) {
    return this.caregiverService.updateCode(user.sub, dto, ip);
  }

  @Post('profile/selfie')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: Validation.FILE_MAX_SIZE_BYTES } }))
  uploadSelfie(
    @CurrentUser() user: JwtPayload,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.caregiverService.uploadSelfie(user.sub, file);
  }

  @Post('profile/documents')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: Validation.FILE_MAX_SIZE_BYTES } }))
  uploadDocument(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UploadDocumentDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.caregiverService.uploadDocument(user.sub, dto, file);
  }

  @Get('verification-status')
  getVerificationStatus(@CurrentUser() user: JwtPayload) {
    return this.caregiverService.getVerificationStatus(user.sub);
  }

  @Put('fcm-token')
  @HttpCode(HttpStatus.OK)
  updateFcmToken(@CurrentUser() user: JwtPayload, @Body() dto: UpdateFcmTokenDto) {
    return this.caregiverService.updateFcmToken(user.sub, dto);
  }
}
