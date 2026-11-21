import { Injectable } from '@nestjs/common';
import { AppPlatform, AppVersionAudienceMode, AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { AppMinVersionsRepository } from '../database/repositories/app-min-versions.repository';
import { AppMaintenanceRepository } from '../database/repositories/app-maintenance.repository';
import { AccountSearchRepository } from '../database/repositories/account-search.repository';
import { UpdateAppVersionDto } from './dto/update-app-version.dto';
import { UpdateAppMaintenanceDto } from './dto/update-app-maintenance.dto';

export interface VersionCheckResult {
  update_required: boolean;
  min_version: string;
  store_url: string | null;
  update_message: string | null;
}

export interface MaintenanceCheckResult {
  enabled: boolean;
  message: string | null;
}

@Injectable()
export class AppConfigService {
  constructor(
    private readonly appMinVersionsRepo: AppMinVersionsRepository,
    private readonly appMaintenanceRepo: AppMaintenanceRepository,
    private readonly auditService: AuditService,
    private readonly accountSearchRepo: AccountSearchRepository,
  ) {}

  /** Public — called once on every cold launch, before login, by the
   *  single JustHeal binary (covers both the caregiver and patient/
   *  hospital flows — see CLAUDE.md's "Merged into one binary with
   *  NurseJobs"). An unrecognized platform 404s (GEN_002) rather than
   *  silently passing, since a malformed/unexpected client is exactly the
   *  case we don't want to fail open on the "does this row exist" check
   *  for. */
  async checkVersion(platform: AppPlatform, version: string, callerUserId?: string | null): Promise<VersionCheckResult> {
    const row = await this.appMinVersionsRepo.findByPlatform(platform);
    if (!row) throw new AppException('GEN_002');

    // A minimum aimed at selected categories / accounts only binds them. Not knowing who is asking (the
    // call before anyone has signed in) never blocks under a selected audience; the app asks again each
    // time an account signs in, with that account's token.
    const updateRequired =
      this.isBelowMinVersion(version, row.min_version) && (await this.appliesToCaller(row, callerUserId));
    return {
      update_required: updateRequired,
      min_version: row.min_version,
      store_url: updateRequired ? row.store_url : null,
      update_message: updateRequired ? row.update_message : null,
    };
  }

  /** Does this row's audience include the account asking? 'all' (or a row that predates audiences)
   *  includes everyone, signed in or not; 'selected' includes an account named in it or in one of its
   *  categories, and never an anonymous caller or an admin. */
  private async appliesToCaller(
    row: { audience_mode?: string; audience_categories?: string[]; audience_user_ids?: string[] },
    callerUserId?: string | null,
  ): Promise<boolean> {
    if (!row.audience_mode || row.audience_mode === AppVersionAudienceMode.ALL) return true;
    if (!callerUserId) return false;
    if ((row.audience_user_ids ?? []).includes(callerUserId)) return true;
    const categories = row.audience_categories ?? [];
    if (categories.length === 0) return false;
    const category = await this.appMinVersionsRepo.categoryOfUser(callerUserId);
    return category != null && categories.includes(category);
  }

  adminList() {
    return this.appMinVersionsRepo.findAll();
  }

  /** Admin picker: caregiver / patient / organisation accounts matching [query] (name, phone, NUR-/PAT-/ORG-
   *  id, organisation name), optionally narrowed to one audience category. At least 2 characters, so the
   *  whole user base is never dumped. */
  async searchAccounts(query: string, category: string | null) {
    const q = query.trim();
    if (q.length < 2) return [];
    return this.accountSearchRepo.search(q, category);
  }

  /** platform comes from an unvalidated @Param segment — an invalid value
   *  simply won't match a row (findByPlatform returns null), which we
   *  turn into the same GEN_002 as a legitimate platform that's somehow
   *  missing. */
  async adminUpdate(adminId: string, platform: string, dto: UpdateAppVersionDto, ipAddress: string | null) {
    const existing = await this.appMinVersionsRepo.findByPlatform(platform);
    if (!existing) throw new AppException('GEN_002');

    const audience = await this.resolveAudience(dto);
    const updated = await this.appMinVersionsRepo.update(platform, { ...dto, audience }, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.APP_VERSION_UPDATED,
      entityType: 'app_min_versions',
      beforeValue: {
        platform,
        min_version: existing.min_version,
        store_url: existing.store_url,
        audience_mode: existing.audience_mode,
        audience_categories: existing.audience_categories,
        audience_user_count: (existing.audience_user_ids ?? []).length,
      },
      afterValue: {
        platform,
        min_version: dto.min_version,
        store_url: dto.store_url ?? null,
        audience_mode: updated.audience_mode,
        audience_categories: updated.audience_categories,
        audience_user_count: (updated.audience_user_ids ?? []).length,
      },
      ipAddress,
    });

    return updated;
  }

  /** The audience to store from an edit, or undefined to leave it untouched (no audience_mode sent).
   *  'all' clears the lists; 'selected' needs at least one category or account, and every named account
   *  must exist (GEN_001 otherwise) — a rule that matches nobody would silently do nothing. */
  private async resolveAudience(
    dto: UpdateAppVersionDto,
  ): Promise<{ mode: 'all' | 'selected'; categories: string[]; user_ids: string[] } | undefined> {
    if (!dto.audience_mode) return undefined;
    if (dto.audience_mode === AppVersionAudienceMode.ALL) return { mode: 'all', categories: [], user_ids: [] };

    const categories = [...new Set(dto.audience_categories ?? [])];
    const userIds = [...new Set(dto.audience_user_ids ?? [])];
    if (categories.length === 0 && userIds.length === 0) throw new AppException('GEN_001');
    if (userIds.length > 0 && (await this.accountSearchRepo.countExisting(userIds)) !== userIds.length) {
      throw new AppException('GEN_001');
    }
    return { mode: 'selected', categories, user_ids: userIds };
  }

  /** Public — called once on every cold launch, before login, alongside
   *  checkVersion, by the single JustHeal binary. */
  async checkMaintenance(): Promise<MaintenanceCheckResult> {
    const row = await this.appMaintenanceRepo.find();
    if (!row) throw new AppException('GEN_002');

    return {
      enabled: row.enabled,
      message: row.enabled ? row.message : null,
    };
  }

  adminMaintenance() {
    return this.appMaintenanceRepo.findWithUpdater();
  }

  async adminMaintenanceUpdate(adminId: string, dto: UpdateAppMaintenanceDto, ipAddress: string | null) {
    const existing = await this.appMaintenanceRepo.find();
    if (!existing) throw new AppException('GEN_002');

    const updated = await this.appMaintenanceRepo.update(dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.APP_MAINTENANCE_UPDATED,
      entityType: 'app_maintenance',
      beforeValue: { enabled: existing.enabled, message: existing.message },
      afterValue: { enabled: dto.enabled, message: dto.message ?? null },
      ipAddress,
    });

    return updated;
  }

  /** Never throws — an unparseable segment (missing/non-numeric) counts
   *  as 0, so a malformed version string just can't out-rank a real one
   *  rather than crashing the launch-time check. */
  private isBelowMinVersion(current: string, min: string): boolean {
    const parse = (v: string) => v.split('.').map((part) => parseInt(part, 10) || 0);
    const [c1, c2, c3] = parse(current);
    const [m1, m2, m3] = parse(min);
    if (c1 !== m1) return c1 < m1;
    if (c2 !== m2) return c2 < m2;
    return c3 < m3;
  }
}
