import { Injectable } from '@nestjs/common';
import { AppPlatform, AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { AppMinVersionsRepository } from '../database/repositories/app-min-versions.repository';
import { AppMaintenanceRepository } from '../database/repositories/app-maintenance.repository';
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
  ) {}

  /** Public — called once on every cold launch, before login, by the
   *  single JustHeal binary (covers both the caregiver and patient/
   *  hospital flows — see CLAUDE.md's "Merged into one binary with
   *  NurseJobs"). An unrecognized platform 404s (GEN_002) rather than
   *  silently passing, since a malformed/unexpected client is exactly the
   *  case we don't want to fail open on the "does this row exist" check
   *  for. */
  async checkVersion(platform: AppPlatform, version: string): Promise<VersionCheckResult> {
    const row = await this.appMinVersionsRepo.findByPlatform(platform);
    if (!row) throw new AppException('GEN_002');

    const updateRequired = this.isBelowMinVersion(version, row.min_version);
    return {
      update_required: updateRequired,
      min_version: row.min_version,
      store_url: updateRequired ? row.store_url : null,
      update_message: updateRequired ? row.update_message : null,
    };
  }

  adminList() {
    return this.appMinVersionsRepo.findAll();
  }

  /** platform comes from an unvalidated @Param segment — an invalid value
   *  simply won't match a row (findByPlatform returns null), which we
   *  turn into the same GEN_002 as a legitimate platform that's somehow
   *  missing. */
  async adminUpdate(adminId: string, platform: string, dto: UpdateAppVersionDto, ipAddress: string | null) {
    const existing = await this.appMinVersionsRepo.findByPlatform(platform);
    if (!existing) throw new AppException('GEN_002');

    const updated = await this.appMinVersionsRepo.update(platform, dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.APP_VERSION_UPDATED,
      entityType: 'app_min_versions',
      beforeValue: { platform, min_version: existing.min_version, store_url: existing.store_url },
      afterValue: { platform, min_version: dto.min_version, store_url: dto.store_url ?? null },
      ipAddress,
    });

    return updated;
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
