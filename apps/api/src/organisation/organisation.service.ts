import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { OrganisationProfilesRepository } from '../database/repositories/organisation-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';
import { UpdateOrganisationProfileDto } from './dto/update-organisation-profile.dto';
import { UpdateFcmTokenDto } from '../caregiver/dto/update-fcm-token.dto';
import { DeleteAccountDto } from '../caregiver/dto/delete-account.dto';

/** Organisation account identity + self-service (phone/PIN change) — the
 *  requirement-posting/applicant-review surface lives in
 *  OrganisationRequirementsService instead, mirroring the individual/jobs
 *  split. No re-review/verification pipeline to trigger on phone change,
 *  same as an individual account. */
@Injectable()
export class OrganisationService {
  constructor(
    private readonly organisationProfilesRepo: OrganisationProfilesRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  async getMe(userId: string) {
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');
    const profile = await this.organisationProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    return {
      user_id: user.id,
      org_number: profile.org_number,
      organisation_name: profile.organisation_name,
      contact_person_name: profile.contact_person_name,
      organisation_type: profile.organisation_type,
      city: profile.city,
      area: profile.area,
      phone: user.phone,
      is_job_posting_blocked: profile.is_job_posting_blocked,
    };
  }

  async updatePhone(userId: string, dto: UpdatePhoneDto, ipAddress: string | null) {
    const profile = await this.organisationProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');
    if (dto.phone === user.phone) return { message: 'Phone number updated' };

    const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [
      UserRole.INDIVIDUAL,
      UserRole.ORGANISATION,
    ]);
    if (existing) throw new AppException('AUTH_001');

    await this.usersRepo.updatePhone(userId, dto.phone);
    await this.auditService.log({
      userId,
      action: AuditAction.PHONE_CHANGED,
      entityType: 'organisation_profiles',
      entityId: profile.id,
      beforeValue: { phone: user.phone },
      afterValue: { phone: dto.phone },
      ipAddress,
    });
    return { message: 'Phone number updated' };
  }

  /** Org self-service edit of every org-owned profile field (name, contact
   *  person, type, city, area) — previously only admin could change these
   *  (PUT /admin/organisations/:id). Mirrors AdminOrganisationsService.
   *  editProfile's diff-only-what-changed-then-audit-log pattern exactly,
   *  including keeping full_name in sync across both users.full_name and
   *  organisation_profiles.contact_person_name. No re-review pipeline to
   *  trigger either way, same as phone/code changes. */
  async updateProfile(userId: string, dto: UpdateOrganisationProfileDto, ipAddress: string | null) {
    const profile = await this.organisationProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user) throw new AppException('GEN_002');

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    const trackedFields = ['full_name', 'organisation_name', 'organisation_type', 'city', 'area'] as const;
    const current: Record<string, unknown> = {
      full_name: user.full_name,
      organisation_name: profile.organisation_name,
      organisation_type: profile.organisation_type,
      city: profile.city,
      area: profile.area,
    };
    for (const field of trackedFields) {
      const nextValue = dto[field];
      if (nextValue === undefined) continue;
      if (current[field] !== nextValue) {
        before[field] = current[field];
        after[field] = nextValue;
      }
    }

    if (dto.full_name !== undefined) {
      await this.usersRepo.updateFullName(userId, dto.full_name);
    }
    await this.organisationProfilesRepo.update(userId, {
      organisation_name: dto.organisation_name,
      contact_person_name: dto.full_name,
      organisation_type: dto.organisation_type,
      city: dto.city,
      area: dto.area,
    });

    if (Object.keys(after).length > 0) {
      await this.auditService.log({
        userId,
        action: AuditAction.PROFILE_UPDATED,
        entityType: 'organisation_profiles',
        entityId: profile.id,
        beforeValue: before,
        afterValue: after,
        ipAddress,
      });
    }

    return { message: 'Profile updated' };
  }

  async updateCode(userId: string, dto: UpdateCodeDto, ipAddress: string | null) {
    const profile = await this.organisationProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');

    const codeHash = await bcrypt.hash(dto.code, Config.BCRYPT_SALT_ROUNDS);
    await this.usersRepo.updateCodeHash(userId, codeHash);
    await this.auditService.log({
      userId,
      action: AuditAction.CODE_CHANGED,
      entityType: 'organisation_profiles',
      entityId: profile.id,
      ipAddress,
    });
    return { message: 'Login code updated' };
  }

  /** Self-service account deletion. The contact person's own name is
   *  anonymized alongside the users row; organisation_name/type/city/area
   *  describe the business entity itself and are left intact (see
   *  OrganisationProfilesRepository.anonymizeContactPerson). */
  async deleteAccount(userId: string, dto: DeleteAccountDto, ipAddress: string | null = null) {
    const profile = await this.organisationProfilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('GEN_002');
    const user = await this.usersRepo.findById(userId);
    if (!user?.code_hash || !(await bcrypt.compare(dto.code, user.code_hash))) {
      throw new AppException('AUTH_008');
    }

    await this.usersRepo.anonymizeAndDeactivate(userId);
    await this.organisationProfilesRepo.anonymizeContactPerson(profile.id);

    await this.auditService.log({
      userId,
      action: AuditAction.ACCOUNT_DELETED,
      entityType: 'organisation_profiles',
      entityId: profile.id,
      ipAddress,
    });

    return { message: 'Account deleted' };
  }

  async updateFcmToken(userId: string, dto: UpdateFcmTokenDto) {
    await this.usersRepo.updateFcmToken(userId, dto.token);
    return { message: 'FCM token updated' };
  }
}
