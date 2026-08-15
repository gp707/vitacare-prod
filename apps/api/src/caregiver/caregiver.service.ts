import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, DocumentType, Validation } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import {
  CaregiverProfilesRepository,
  CaregiverProfileFullRecord,
} from '../database/repositories/caregiver-profiles.repository';
import { CaregiverLanguagesRepository } from '../database/repositories/caregiver-languages.repository';
import { CaregiverServiceModesRepository } from '../database/repositories/caregiver-service-modes.repository';
import { CaregiverWorkTypesRepository } from '../database/repositories/caregiver-work-types.repository';
import { CaregiverPreferredCitiesRepository } from '../database/repositories/caregiver-preferred-cities.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { DatabaseService } from '../database/database.service';
import { EmailService } from '../email/email.service';
import { AuditService } from '../audit/audit.service';
import { UploadService } from '../upload/upload.service';
import { UpdateBasicProfileDto } from './dto/update-basic-profile.dto';
import { SubmitAdvancedDetailsDto } from './dto/submit-advanced-details.dto';
import { EditAdvancedProfileDto } from './dto/edit-advanced-profile.dto';
import { UpdatePhoneDto } from './dto/update-phone.dto';
import { UpdateCodeDto } from './dto/update-code.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { UpdateFcmTokenDto } from './dto/update-fcm-token.dto';

const CALL_VERIFIED_OR_REJECTED = ['call_verified', 'rejected'];
// Only these two statuses have an existing "re-review" transition back to
// pending_verification in the matrix (previously admin-manual, unbuilt) —
// in_process/assigned are deliberately excluded per product decision, so an
// identity-sensitive edit mid-review or mid-assignment doesn't yank the
// caregiver out of that state.
const RE_REVIEW_ELIGIBLE_STATUSES = ['available', 'unavailable'];

@Injectable()
export class CaregiverService {
  constructor(
    private readonly db: DatabaseService,
    private readonly usersRepo: UsersRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly languagesRepo: CaregiverLanguagesRepository,
    private readonly serviceModesRepo: CaregiverServiceModesRepository,
    private readonly workTypesRepo: CaregiverWorkTypesRepository,
    private readonly preferredCitiesRepo: CaregiverPreferredCitiesRepository,
    private readonly uploadService: UploadService,
    private readonly emailService: EmailService,
    private readonly auditService: AuditService,
  ) {}

  async getProfile(userId: string) {
    const profile = await this.requireFullProfile(userId);
    const [languages, serviceModes, workTypes, preferredCities] = await Promise.all([
      this.languagesRepo.findByProfileId(profile.id),
      this.serviceModesRepo.findByProfileId(profile.id),
      this.workTypesRepo.findByProfileId(profile.id),
      this.preferredCitiesRepo.findByProfileId(profile.id),
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
      service_modes: serviceModes,
      work_types: workTypes,
      salary: profile.salary === null ? null : Number(profile.salary),
      highest_qualification: profile.highest_qualification,
      qualification_document_url: qualificationUrl,
      aadhaar_document_url: aadhaarUrl,
      other_document_urls: otherUrls,
      religion: profile.religion,
      terms_accepted: profile.terms_accepted,
      verification_status: profile.verification_status,
      rejection_message: profile.rejection_message,
      advanced_details_completed: profile.advanced_details_completed,
      preferred_cities: preferredCities,
      created_at: profile.created_at,
    };
  }

  async updateBasicProfile(userId: string, dto: UpdateBasicProfileDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);
    const previousLanguages = await this.languagesRepo.findByProfileId(profile.id);

    await this.db.withTransaction(async (client) => {
      await this.profilesRepo.updateBasic(
        profile.id,
        { age: dto.age },
        client,
      );
      await this.languagesRepo.replaceForProfile(profile.id, dto.languages, client);
    });

    await this.recordBasicProfileChange(userId, profile, previousLanguages, dto, ipAddress);

    return {
      message: 'Profile updated',
      has_pending_edits: true,
      verification_status: profile.verification_status,
    };
  }

  /** Diffs old vs. new basic-profile fields once and reuses it for both the
   *  admin notification email and the audit log's before/after values —
   *  both only ever describe fields that actually changed. */
  private async recordBasicProfileChange(
    userId: string,
    previous: { id: string; full_name: string; age: number },
    previousLanguages: string[],
    next: UpdateBasicProfileDto,
    ipAddress: string | null,
  ): Promise<void> {
    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    const changeLines: string[] = [];

    if (previous.age !== next.age) {
      before.age = previous.age;
      after.age = next.age;
      changeLines.push(`age: ${previous.age} -> ${next.age}`);
    }
    const prevLangs = [...previousLanguages].sort();
    const nextLangs = [...next.languages].sort();
    if (prevLangs.join(',') !== nextLangs.join(',')) {
      before.languages = prevLangs;
      after.languages = nextLangs;
      changeLines.push(`languages: [${prevLangs.join(', ')}] -> [${nextLangs.join(', ')}]`);
    }
    if (changeLines.length === 0) return;

    await this.emailService.sendToAdmin(
      'Caregiver profile updated (pending review)',
      `${previous.full_name} updated their profile:\n${changeLines.join('\n')}`,
    );

    await this.auditService.log({
      userId,
      action: AuditAction.PROFILE_UPDATED,
      entityType: 'caregiver_profiles',
      entityId: previous.id,
      beforeValue: before,
      afterValue: after,
      ipAddress,
    });
  }

  /** Phone is identity-sensitive: changing it re-sends a verified/available
   *  caregiver for review (unlike every other self-editable field). */
  async updatePhone(userId: string, dto: UpdatePhoneDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);
    if (dto.phone === profile.phone) {
      return { message: 'Phone number updated', verification_status: profile.verification_status };
    }

    const existing = await this.usersRepo.findByPhone(dto.phone);
    if (existing) throw new AppException('AUTH_001');

    await this.usersRepo.updatePhone(userId, dto.phone);
    const wasReReviewed = await this.triggerReReviewIfEligible(profile);

    await this.emailService.sendToAdmin(
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
      verification_status: wasReReviewed ? 'pending_verification' : profile.verification_status,
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

  /** Self-edit of the advanced-details fields any time after the initial
   *  submission — unlike submitAdvancedDetails (one-time/resubmission-only,
   *  whole-object, resets status to pending_verification), this is a
   *  partial update that never touches verification_status. */
  async editAdvancedProfile(userId: string, dto: EditAdvancedProfileDto, ipAddress: string | null = null) {
    const profile = await this.requireFullProfile(userId);
    if (!profile.advanced_details_completed) {
      throw new AppException('PROFILE_025');
    }

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    const fields: (keyof EditAdvancedProfileDto)[] = ['highest_qualification'];
    for (const field of fields) {
      if (dto[field] === undefined) continue;
      const previousValue = profile[field as keyof CaregiverProfileFullRecord] ?? null;
      if (previousValue === dto[field]) continue;
      before[field] = previousValue;
      after[field] = dto[field];
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

    const scalarFieldsChanged = Object.keys(after).some((field) => field !== 'preferred_cities');

    if (scalarFieldsChanged) {
      await this.profilesRepo.editAdvancedFields(profile.id, {
        highest_qualification: dto.highest_qualification,
      });
    } else if (citiesChanged) {
      await this.profilesRepo.flagPendingEdits(profile.id);
    }

    if (citiesChanged) {
      await this.preferredCitiesRepo.replaceForProfile(profile.id, dto.preferred_cities!);
    }

    if (Object.keys(after).length > 0) {
      await this.emailService.sendToAdmin(
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

    return { message: 'Profile updated', has_pending_edits: true };
  }

  /** Re-sends a caregiver for review after an identity-sensitive change,
   *  but only from the two statuses where that's an existing, safe
   *  transition (available/unavailable) — never mid-review (in_process) or
   *  mid-assignment (assigned), so this can't yank someone off an active
   *  job or interrupt an admin's in-progress review. Returns whether the
   *  reset actually happened, for the caller's response/email wording. */
  private async triggerReReviewIfEligible(profile: { id: string; verification_status: string }): Promise<boolean> {
    if (!RE_REVIEW_ELIGIBLE_STATUSES.includes(profile.verification_status)) return false;
    await this.profilesRepo.markForReReview(profile.id);
    return true;
  }

  async submitAdvancedDetails(
    userId: string,
    dto: SubmitAdvancedDetailsDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.requireFullProfile(userId);

    if (!CALL_VERIFIED_OR_REJECTED.includes(profile.verification_status)) {
      throw new AppException('PROFILE_008');
    }
    // Selfie is already guaranteed by registration (Stage 1); of the
    // documents uploaded here, only Aadhaar is mandatory — qualification
    // and "other" documents are optional.
    if (!profile.aadhaar_document_url) {
      throw new AppException('PROFILE_017');
    }

    await this.profilesRepo.updateAdvanced(profile.id, {
      highest_qualification: dto.highest_qualification,
    });

    await this.emailService.sendToAdmin(
      'Advanced details submitted — pending document review',
      `${profile.full_name} (${profile.phone}) submitted advanced details and is ready for document review.`,
    );

    await this.auditService.log({
      userId,
      action: AuditAction.ADVANCED_DETAILS_SUBMITTED,
      entityType: 'caregiver_profiles',
      entityId: profile.id,
      afterValue: {
        highest_qualification: dto.highest_qualification,
      },
      ipAddress,
    });

    return { message: 'Advanced details submitted', verification_status: 'pending_verification' };
  }

  async uploadSelfie(userId: string, file: Express.Multer.File | undefined) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.requireProfile(userId);

    const ext = this.uploadService.extractExtension(file.originalname);
    const path = `${profile.id}/selfie${ext ? `.${ext}` : ''}`;
    await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
    await this.profilesRepo.setSelfieUrl(profile.id, path);

    return { message: 'Selfie uploaded', file_path: `${Config.STORAGE_BUCKET}/${path}` };
  }

  async uploadDocument(
    userId: string,
    dto: UploadDocumentDto,
    file: Express.Multer.File | undefined,
  ) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.requireProfile(userId);
    const ext = this.uploadService.extractExtension(file.originalname);

    let path: string;
    if (dto.document_type === DocumentType.QUALIFICATION) {
      path = `${profile.id}/qualification${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.setQualificationDocumentUrl(profile.id, path);
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
      submitted_at: profile.submitted_at,
      verified_at: profile.verified_at,
    };
  }

  async updateFcmToken(userId: string, dto: UpdateFcmTokenDto) {
    await this.usersRepo.updateFcmToken(userId, dto.token);
    return { message: 'FCM token updated' };
  }

  private async requireProfile(userId: string) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return profile;
  }

  private async requireFullProfile(userId: string): Promise<CaregiverProfileFullRecord> {
    const profile = await this.profilesRepo.findFullByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    return profile;
  }
}
