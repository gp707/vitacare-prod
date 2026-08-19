import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { OrganisationProfilesRepository } from '../database/repositories/organisation-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { UpdatePhoneDto } from '../caregiver/dto/update-phone.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';

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
}
