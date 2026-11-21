import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AppVersionAudienceCategory, UserRole } from '@vitacare/shared-constants';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { AppConfigService } from './app-config.service';

class AccountSearchQueryDto {
  @IsString({ message: 'GEN_001' })
  @MaxLength(100, { message: 'GEN_001' })
  q!: string;

  @IsOptional()
  @IsIn(Object.values(AppVersionAudienceCategory), { message: 'GEN_001' })
  category?: AppVersionAudienceCategory;
}

/** Admin picker over caregiver / patient / organisation accounts. */
@Controller('admin/accounts')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN, UserRole.SUPER_ADMIN)
export class AdminAccountSearchController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get('search')
  search(@Query() query: AccountSearchQueryDto) {
    return this.appConfigService.searchAccounts(query.q, query.category ?? null);
  }
}
