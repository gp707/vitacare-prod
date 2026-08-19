import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, DocumentType, Validation } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import {
  CaregiverProfilesRepository,
  CaregiverProfileFullRecord,
} from '../database/repositories/caregiver-profiles.repository';
import { CaregiverLanguagesRepository } from '../database/repositories/caregiver-languages.repository';
import { CaregiverPreferredCitiesRepository } from '../database/repositories/caregiver-preferred-cities.repository';
import { CaregiverPreferredDutyTypesRepository } from '../database/repositories/caregiver-preferred-duty-types.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { DatabaseService } from '../database/database.service';
import { EmailService } from '../email/email.service';
import { AuditService } from '../audit/audit.service';
import { UploadService } from '../upload/upload.service';
import { EditProfileDto } from './dto/edit-profile.dto';
import { UpdatePhoneDto } from './dto/update-phone.dto';
import { UpdateCodeDto } from './dto/update-code.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { UpdateFcmTokenDto } from './dto/update-fcm-token.dto';

// Identity-sensitive changes (phone, Aadhaar re-upload) send a caregiver
// back to pending_call for re-review from these statuses. assigned is
// deliberately excluded — this can't yank someone off an active job.
// rejected is included here (not just available/unavailable)
// so fixing the flagged identity document also auto-resubmits.
const IDENTITY_SENSITIVE_REVIEW_STATUSES = ['available', 'unavailable', 'rejected'];

@Injectable()
export class CaregiverService {
  constructor(
    private readonly db: DatabaseService,
    private readonly usersRepo: UsersRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly languagesRepo: CaregiverLanguagesRepository,
    private readonly preferredCitiesRepo: CaregiverPreferredCitiesRepository,
    private readonly preferredDutyTypesRepo: CaregiverPreferredDutyTypesRepository,
    private readonly uploadService: UploadService,
    private readonly emailService: EmailService,
    private readonly auditService: AuditService,
  ) {}

  async getProfile(userId: string) {
    const profile = await this.requireFullProfile(userId);
    const [languages, preferredCities, preferredDutyTypes] = await Promise.all([
      this.languagesRepo.findByProfileId(profile.id),
      this.preferredCitiesRepo.findByProfileId(profile.id),
      this.preferredDutyTypesRepo.findByProfileId(profile.id),
    ]);

    const [selfieUrl, qualificationUrl, aadhaarUrl, otherUrls] = await Promise.all([
      this.uploadService.getSignedUrlOrNull(Config.STORAGE_BUCKET, profile.selfie_photo_url),
      this.uploadService.getSignedUrlOrNull(
        Config.STORAGE_BUCKET,
        profile.qualification_document_url,
      ),
      this.uploadService.getSignedUrlOrNull(Config.STORAGE_BUCKET, profile.aadhaar_document_url),
      Promise.all(
        (profile.other_document_urls ?? []).map((path) =>
          this.uploadService.getSignedUrl(Config.STORAGE_BUCKET, path),
        ),
      ),
    ]);

    return {
      user_id: profile.user_id,
      profile_id: profile.id,
      full_name: profile.full_name,
      phone: profile.phone,
      email: profile.email,
      gender: profile.gender,
      age: profile.age,
      selfie_photo_url: selfieUrl,
      languages,
      highest_qualification: profile.highest_qualification,
      qualification_document_url: qualificationUrl,
      aadhaar_document_url: aadhaarUrl,
      other_document_urls: otherUrls,
      religion: profile.religion,
      terms_accepted: profile.terms_accepted,
      verification_status: profile.verification_status,
      rejection_message: profile.rejection_message,
      preferred_cities: preferredCities,
      preferred_duty_types: preferredDutyTypes,
      min_salary_per_day: profile.min_salary_per_day,
      min_salary_per_month: profile.min_salary_per_month,
      created_at: profile.created_at,
    };
  }

  /** The profile shown to an individual/organisation reviewing a caregiver
   *  who applied to their job/requirement — deliberately a smaller subset
   *  than getProfile()/admin's own caregiver detail: no email, no
   *  Aadhaar/qualification-document links, no other_document_urls, no
   *  job-search preferences (preferred_cities/duty_types/min_salary) or
   *  rejection_message — none of that is this viewer's business, and
   *  keeping the payload lean keeps the profile screen from feeling
   *  crowded. Same JSON shape as getProfile() for the fields it does
   *  return, so CaregiverProfileModel.fromJson on the client parses either
   *  one unchanged (the omitted fields are all nullable/list-defaulted on
   *  that model). Callers (IndividualService/OrganisationRequirementsService)
   *  do their own job/requirement + application ownership check before
   *  calling this — this method itself doesn't know who's asking. */
  async getApplicantProfile(profileId: string) {
    const profile = await this.profilesRepo.findFullById(profileId);
    if (!profile) throw new AppException('GEN_002');
    const languages = await this.languagesRepo.findByProfileId(profile.id);
    const selfieUrl = await this.uploadService.getSignedUrlOrNull(
      Config.STORAGE_BUCKET,
      profile.selfie_photo_url,
    );

    return {
      user_id: profile.user_id,
      profile_id: profile.id,
      full_name: profile.full_name,
      phone: profile.phone,
      gender: profile.gender,
      age: profile.age,
      selfie_photo_url: selfieUrl,
      languages,
      highest_qualification: profile.highest_qualification,
      religion: profile.religion,
      terms_accepted: profile.terms_accepted,
      verification_status: profile.verification_status,
      created_at: profile.created_at,
    };
  }

  /** Single self-edit endpoint for every caregiver-editable field — age,
   *  languages, highest_qualification, preferred_cities. full_name, gender,
   *  and religion are intentionally absent — locked from self-edit once set
   *  at registration; only admins can change them (see update-phone.dto.ts
   *  and update-code.dto.ts for the identity-sensitive fields that live on
   *  their own endpoints, each with different review-trigger semantics).
   *  Any subset of fields — only what's provided gets written/diffed.
   *  While rejected, any actual change here auto-resubmits (sends the
   *  caregiver back to pending_call) instead of just flagging
   *  has_pending_edits — no separate "resubmit" action needed. */
  async editProfile(userId: string, dto: EditProfileDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};

    if (dto.age !== undefined && dto.age !== profile.age) {
      before.age = profile.age;
      after.age = dto.age;
    }
    if (
      dto.highest_qualification !== undefined &&
      dto.highest_qualification !== profile.highest_qualification
    ) {
      before.highest_qualification = profile.highest_qualification;
      after.highest_qualification = dto.highest_qualification;
    }
    if (
      dto.min_salary_per_day !== undefined &&
      dto.min_salary_per_day !== profile.min_salary_per_day
    ) {
      before.min_salary_per_day = profile.min_salary_per_day;
      after.min_salary_per_day = dto.min_salary_per_day;
    }
    if (
      dto.min_salary_per_month !== undefined &&
      dto.min_salary_per_month !== profile.min_salary_per_month
    ) {
      before.min_salary_per_month = profile.min_salary_per_month;
      after.min_salary_per_month = dto.min_salary_per_month;
    }

    let languagesChanged = false;
    if (dto.languages !== undefined) {
      const previousLanguages = await this.languagesRepo.findByProfileId(profile.id);
      const prevSorted = [...previousLanguages].sort();
      const nextSorted = [...dto.languages].sort();
      if (prevSorted.join(',') !== nextSorted.join(',')) {
        before.languages = prevSorted;
        after.languages = nextSorted;
        languagesChanged = true;
      }
    }

    let citiesChanged = false;
    if (dto.preferred_cities !== undefined) {
      const previousCities = await this.preferredCitiesRepo.findByProfileId(profile.id);
      const prevSorted = [...previousCities].sort();
      const nextSorted = [...dto.preferred_cities].sort();
      if (prevSorted.join(',') !== nextSorted.join(',')) {
        before.preferred_cities = prevSorted;
        after.preferred_cities = nextSorted;
        citiesChanged = true;
      }
    }

    let dutyTypesChanged = false;
    if (dto.preferred_duty_types !== undefined) {
      const previousDutyTypes = await this.preferredDutyTypesRepo.findByProfileId(profile.id);
      const prevSorted = [...previousDutyTypes].sort();
      const nextSorted = [...dto.preferred_duty_types].sort();
      if (prevSorted.join(',') !== nextSorted.join(',')) {
        before.preferred_duty_types = prevSorted;
        after.preferred_duty_types = nextSorted;
        dutyTypesChanged = true;
      }
    }

    const scalarFieldsChanged = Object.keys(after).some(
      (field) =>
        field !== 'preferred_cities' && field !== 'languages' && field !== 'preferred_duty_types',
    );
    const anyChanged = scalarFieldsChanged || languagesChanged || citiesChanged || dutyTypesChanged;

    await this.db.withTransaction(async (client) => {
      if (scalarFieldsChanged) {
        await this.profilesRepo.editFields(profile.id, {
          age: dto.age,
          highest_qualification: dto.highest_qualification,
          min_salary_per_day: dto.min_salary_per_day,
          min_salary_per_month: dto.min_salary_per_month,
        });
      } else if (anyChanged) {
        // languages/preferred_cities/preferred_duty_types-only change —
        // editFields would be a no-op for an all-undefined input, so flag
        // explicitly instead.
        await this.profilesRepo.flagPendingEdits(profile.id);
      }
      if (languagesChanged) {
        await this.languagesRepo.replaceForProfile(profile.id, dto.languages!, client);
      }
      if (citiesChanged) {
        await this.preferredCitiesRepo.replaceForProfile(profile.id, dto.preferred_cities!, client);
      }
      if (dutyTypesChanged) {
        await this.preferredDutyTypesRepo.replaceForProfile(
          profile.id,
          dto.preferred_duty_types!,
          client,
        );
      }
    });

    const wasResubmitted = anyChanged && (await this.triggerResubmitIfRejected(profile));

    if (anyChanged) {
      void this.emailService.sendToAdmin(
        'Caregiver profile updated (pending review)',
        `${profile.full_name} updated their profile:\n` +
          Object.keys(after)
            .map((field) => `${field}: "${before[field]}" -> "${after[field]}"`)
            .join('\n'),
      );
      await this.auditService.log({
        userId,
        action: AuditAction.PROFILE_UPDATED,
        entityType: 'caregiver_profiles',
        entityId: profile.id,
        beforeValue: before,
        afterValue: after,
        ipAddress,
      });
    }

    return {
      message: 'Profile updated',
      has_pending_edits: true,
      verification_status: wasResubmitted ? 'pending_call' : profile.verification_status,
    };
  }

  /** Phone is identity-sensitive: changing it re-sends a verified/available/
   *  rejected caregiver for review (unlike every other self-editable field). */
  async updatePhone(userId: string, dto: UpdatePhoneDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);
    if (dto.phone === profile.phone) {
      return { message: 'Phone number updated', verification_status: profile.verification_status };
    }

    const existing = await this.usersRepo.findByPhone(dto.phone);
    if (existing) throw new AppException('AUTH_001');

    await this.usersRepo.updatePhone(userId, dto.phone);
    const wasReReviewed = await this.triggerReReviewIfEligible(profile);

    void this.emailService.sendToAdmin(
      'Caregiver phone number changed',
      `${profile.full_name} changed their phone number from ${profile.phone} to ${dto.phone}.` +
        (wasReReviewed ? ' Their profile has been sent back for re-review.' : ''),
    );
    await this.auditService.log({
      userId,
      action: AuditAction.PHONE_CHANGED,
      entityType: 'caregiver_profiles',
      entityId: profile.id,
      beforeValue: { phone: profile.phone },
      afterValue: { phone: dto.phone },
      ipAddress,
    });

    return {
      message: 'Phone number updated',
      verification_status: wasReReviewed ? 'pending_call' : profile.verification_status,
    };
  }

  /** PIN change never triggers re-review (unlike phone/Aadhaar) — it's
   *  purely an account-security action, not an identity change. */
  async updateCode(userId: string, dto: UpdateCodeDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);
    const codeHash = await bcrypt.hash(dto.code, Config.BCRYPT_SALT_ROUNDS);
    await this.usersRepo.updateCodeHash(userId, codeHash);

    await this.auditService.log({
      userId,
      action: AuditAction.CODE_CHANGED,
      entityType: 'caregiver_profiles',
      entityId: profile.id,
      ipAddress,
    });

    return { message: 'Login code updated' };
  }

  /** Re-sends a caregiver for review after an identity-sensitive change
   *  (phone, Aadhaar), from any of the statuses where that's eligible.
   *  Returns whether the reset actually happened, for the caller's
   *  response/email wording. */
  private async triggerReReviewIfEligible(profile: { id: string; verification_status: string }): Promise<boolean> {
    if (!IDENTITY_SENSITIVE_REVIEW_STATUSES.includes(profile.verification_status)) return false;
    await this.profilesRepo.markForReReview(profile.id);
    return true;
  }

  /** Auto-resubmit: any edit at all while rejected sends the caregiver back
   *  to pending_call — no separate "resubmit" action needed. Unlike
   *  triggerReReviewIfEligible, this never fires for available/unavailable
   *  (those only care about identity-sensitive changes). */
  private async triggerResubmitIfRejected(profile: { id: string; verification_status: string }): Promise<boolean> {
    if (profile.verification_status !== 'rejected') return false;
    await this.profilesRepo.markForReReview(profile.id);
    return true;
  }

  async uploadSelfie(userId: string, file: Express.Multer.File | undefined) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.requireFullProfile(userId);

    const ext = this.uploadService.extractExtension(file.originalname);
    const path = `${profile.id}/selfie${ext ? `.${ext}` : ''}`;
    await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
    await this.profilesRepo.setSelfieUrl(profile.id, path);
    await this.triggerResubmitIfRejected(profile);

    return { message: 'Selfie uploaded', file_path: `${Config.STORAGE_BUCKET}/${path}` };
  }

  async uploadDocument(
    userId: string,
    dto: UploadDocumentDto,
    file: Express.Multer.File | undefined,
  ) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.requireFullProfile(userId);
    const ext = this.uploadService.extractExtension(file.originalname);

    let path: string;
    if (dto.document_type === DocumentType.QUALIFICATION) {
      path = `${profile.id}/qualification${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.setQualificationDocumentUrl(profile.id, path);
      await this.triggerResubmitIfRejected(profile);
    } else if (dto.document_type === DocumentType.AADHAAR) {
      path = `${profile.id}/aadhaar${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.setAadhaarDocumentUrl(profile.id, path);
      // Re-uploading Aadhaar on an already-verified profile is identity-
      // sensitive — send it back for review, same rule as phone changes.
      await this.triggerReReviewIfEligible(profile);
    } else {
      const existing = await this.profilesRepo.getOtherDocumentUrls(profile.id);
      if (existing.length >= Validation.MAX_OTHER_DOCUMENTS) {
        throw new AppException('UPLOAD_003');
      }
      const index = existing.length + 1;
      path = `${profile.id}/other_${index}${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.appendOtherDocumentUrl(profile.id, path);
      await this.triggerResubmitIfRejected(profile);
    }

    return {
      message: 'Document uploaded',
      document_type: dto.document_type,
      file_path: `${Config.STORAGE_BUCKET}/${path}`,
    };
  }

  async getVerificationStatus(userId: string) {
    const profile = await this.requireFullProfile(userId);
    return {
      verification_status: profile.verification_status,
      rejection_message: profile.rejection_message,
      verified_at: profile.verified_at,
    };
  }

  /** One-click self-service "I'm available" — allowed from unavailable or
   *  assigned only. From pending_call/rejected, PROFILE_022 (the caregiver
   *  must instead edit their profile, which auto-resubmits while rejected —
   *  there's no self-service path out of pending_call at all). Already
   *  available is a no-op (no write, no audit entry), so the UI can just
   *  show "you're already available" without a failed request. */
  async markAvailable(userId: string, ipAddress: string | null) {
    const profile = await this.requireFullProfile(userId);

    if (profile.verification_status === 'available') {
      return {
        message: 'You are already marked as available',
        verification_status: 'available' as const,
        already_available: true,
      };
    }

    if (profile.verification_status !== 'unavailable' && profile.verification_status !== 'assigned') {
      throw new AppException('PROFILE_022');
    }

    await this.profilesRepo.markAvailable(profile.id);

    await this.auditService.log({
      userId,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'caregiver_profiles',
      entityId: profile.id,
      beforeValue: { verification_status: profile.verification_status },
      afterValue: { verification_status: 'available' },
      ipAddress,
    });

    return {
      message: 'Status updated',
      verification_status: 'available' as const,
      already_available: false,
    };
  }

  async updateFcmToken(userId: string, dto: UpdateFcmTokenDto) {
    await this.usersRepo.updateFcmToken(userId, dto.token);
    return { message: 'FCM token updated' };
  }

  private async requireFullProfile(userId: string): Promise<CaregiverProfileFullRecord> {
    const profile = await this.profilesRepo.findFullByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return profile;
  }
}
