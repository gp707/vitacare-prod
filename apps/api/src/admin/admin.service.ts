import { Injectable } from '@nestjs/common';
import { AuditAction, Config, DocumentType, Validation } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { AdminCaregiversRepository } from '../database/repositories/admin-caregivers.repository';
import { AdminNotesRepository } from '../database/repositories/admin-notes.repository';
import { AuditLogsRepository } from '../database/repositories/audit-logs.repository';
import { CaregiverLanguagesRepository } from '../database/repositories/caregiver-languages.repository';
import { CaregiverServiceModesRepository } from '../database/repositories/caregiver-service-modes.repository';
import { CaregiverWorkTypesRepository } from '../database/repositories/caregiver-work-types.repository';
import { CaregiverPreferredCitiesRepository } from '../database/repositories/caregiver-preferred-cities.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { DatabaseService } from '../database/database.service';
import { UploadService } from '../upload/upload.service';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { ListCaregiversQueryDto } from './dto/list-caregivers-query.dto';
import { UpdateCaregiverStatusDto } from './dto/update-caregiver-status.dto';
import { UpsertAdminNotesDto } from './dto/upsert-admin-notes.dto';
import { ListAuditLogsQueryDto } from './dto/list-audit-logs-query.dto';
import { AdminEditCaregiverDto } from './dto/admin-edit-caregiver.dto';
import { AssignWorkTypesDto } from './dto/assign-work-types.dto';
import { AssignServiceModesDto } from './dto/assign-service-modes.dto';
import { UpdateSalaryDto } from './dto/update-salary.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';

@Injectable()
export class AdminService {
  constructor(
    private readonly caregiversRepo: AdminCaregiversRepository,
    private readonly notesRepo: AdminNotesRepository,
    private readonly auditLogsRepo: AuditLogsRepository,
    private readonly languagesRepo: CaregiverLanguagesRepository,
    private readonly serviceModesRepo: CaregiverServiceModesRepository,
    private readonly workTypesRepo: CaregiverWorkTypesRepository,
    private readonly preferredCitiesRepo: CaregiverPreferredCitiesRepository,
    private readonly uploadService: UploadService,
    private readonly auditService: AuditService,
    private readonly fcmService: FcmService,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly usersRepo: UsersRepository,
    private readonly db: DatabaseService,
  ) {}

  async getDashboardStats() {
    return this.caregiversRepo.getDashboardStats();
  }

  async listCaregivers(query: ListCaregiversQueryDto) {
    const languages = query.language
      ? query.language.split(',').map((lang) => lang.trim()).filter(Boolean)
      : undefined;

    const { items, total } = await this.caregiversRepo.listCaregivers(
      {
        search: query.search,
        status: query.status,
        qualification: query.qualification,
        languages,
        serviceMode: query.service_mode,
        workType: query.work_type,
        fromDate: query.from_date,
        toDate: query.to_date,
      },
      { sort: query.sort, order: query.order, page: query.page, limit: query.limit },
    );

    const data = items.map((item) => ({
      user_id: item.user_id,
      profile_id: item.profile_id,
      full_name: item.full_name,
      phone: item.phone,
      gender: item.gender,
      age: item.age,
      highest_qualification: item.highest_qualification,
      service_modes: item.service_modes,
      work_types: item.work_types,
      verification_status: item.verification_status,
      created_at: item.created_at,
    }));

    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };

    return { data, meta };
  }

  async getCaregiverDetail(profileId: string) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const [languages, serviceModes, workTypes, preferredCities, notes, selfieUrl, qualificationUrl, aadhaarUrl, otherUrls] =
      await Promise.all([
        this.languagesRepo.findByProfileId(profile.id),
        this.serviceModesRepo.findByProfileId(profile.id),
        this.workTypesRepo.findByProfileId(profile.id),
        this.preferredCitiesRepo.findByProfileId(profile.id),
        this.notesRepo.findByProfileId(profile.id),
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
      religion: profile.religion,
      father_name: profile.father_name,
      father_phone: profile.father_phone,
      qualification_document_url: qualificationUrl,
      aadhaar_document_url: aadhaarUrl,
      other_document_urls: otherUrls,
      current_address: profile.current_address,
      terms_accepted: profile.terms_accepted,
      verification_status: profile.verification_status,
      rejection_message: profile.rejection_message,
      advanced_details_completed: profile.advanced_details_completed,
      has_pending_edits: profile.has_pending_edits,
      preferred_cities: preferredCities,
      notes: profile.notes,
      admin_notes: {
        internal_notes: notes?.internal_notes ?? null,
        rate_24hrs_live_in: notes?.rate_24hrs_live_in === undefined || notes?.rate_24hrs_live_in === null
          ? null
          : Number(notes.rate_24hrs_live_in),
        rate_12hrs_pg: notes?.rate_12hrs_pg === undefined || notes?.rate_12hrs_pg === null
          ? null
          : Number(notes.rate_12hrs_pg),
        availability_remarks: notes?.availability_remarks ?? null,
      },
      created_at: profile.created_at,
      submitted_at: profile.submitted_at,
      verified_at: profile.verified_at,
    };
  }

  async markCallVerified(
    profileId: string,
    adminId: string,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');
    if (profile.verification_status !== 'pending_call') {
      throw new AppException('ADMIN_002');
    }

    await this.caregiversRepo.markCallVerified(profileId, adminId);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.CALL_VERIFIED,
      entityType: 'caregiver_profiles',
      entityId: profileId,
      beforeValue: { verification_status: profile.verification_status },
      afterValue: { verification_status: 'call_verified' },
      ipAddress,
    });

    await this.fcmService.sendToUser(
      profile.user_id,
      'Phone verified',
      'Your phone has been verified. Please fill in your advanced details to continue.',
    );

    return { message: 'Caregiver marked as call verified', verification_status: 'call_verified' };
  }

  /** Admin override — no transition-matrix restriction here deliberately.
   *  Admin can move any caregiver directly to any status; admin-web's own
   *  "Start Review"/"Approve"/"Reject" buttons cover the common-case flow,
   *  this endpoint is also exposed as a free-form override for everything
   *  else (including statuses those buttons never offer, e.g. jumping
   *  straight to `assigned` or back to `pending_call`). */
  async updateStatus(
    profileId: string,
    adminId: string,
    dto: UpdateCaregiverStatusDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    await this.caregiversRepo.updateStatus(
      profileId,
      dto.status,
      dto.status === 'rejected' ? (dto.rejection_message ?? null) : null,
      adminId,
    );

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'caregiver_profiles',
      entityId: profileId,
      beforeValue: { verification_status: profile.verification_status },
      afterValue: {
        verification_status: dto.status,
        ...(dto.status === 'rejected' ? { rejection_message: dto.rejection_message ?? null } : {}),
      },
      ipAddress,
    });

    if (dto.status === 'available') {
      await this.fcmService.sendToUser(
        profile.user_id,
        'Profile approved',
        'Congratulations! Your profile has been approved.',
      );
    } else if (dto.status === 'rejected') {
      await this.fcmService.sendToUser(
        profile.user_id,
        'Profile update',
        dto.rejection_message ?? 'Your profile status has been updated. Please check the app for details.',
      );
    } else if (dto.status === 'in_process') {
      // SPEC.md 6.7's notification table documents this one too — was
      // previously missing (only available/rejected were ever sent).
      await this.fcmService.sendToUser(
        profile.user_id,
        'Profile Under Review',
        "Your documents are being reviewed. We'll update you soon.",
      );
    }

    return { message: 'Status updated', verification_status: dto.status };
  }

  async upsertNotes(
    profileId: string,
    adminId: string,
    dto: UpsertAdminNotesDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const previousNotes = await this.notesRepo.findByProfileId(profileId);
    await this.notesRepo.upsert(profileId, adminId, dto);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.ADMIN_NOTE_ADDED,
      entityType: 'admin_notes',
      entityId: profileId,
      beforeValue: previousNotes ? { ...previousNotes } : null,
      afterValue: { ...dto },
      ipAddress,
    });

    return { message: 'Notes saved' };
  }

  async listAuditLogs(query: ListAuditLogsQueryDto) {
    const { items, total } = await this.auditLogsRepo.list(
      {
        userId: query.user_id,
        targetUserId: query.target_user_id,
        action: query.action,
        fromDate: query.from_date,
        toDate: query.to_date,
      },
      { order: query.order, page: query.page, limit: query.limit },
    );

    const data = items.map((item) => ({
      id: item.id,
      user_id: item.user_id,
      user_name: item.user_name,
      target_user_id: item.target_user_id,
      target_user_name: item.target_user_name,
      action: item.action,
      entity_type: item.entity_type,
      entity_id: item.entity_id,
      before_value: item.before_value,
      after_value: item.after_value,
      ip_address: item.ip_address,
      created_at: item.created_at,
    }));

    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };

    return { data, meta };
  }

  /** Generic admin override for any subset of caregiver profile fields.
   *  Does NOT include service_modes/work_types/salary (dedicated endpoints
   *  below) and does NOT change verification_status — admin edits are
   *  trusted, unlike caregiver self-edits which flag has_pending_edits. */
  async editProfile(
    profileId: string,
    adminId: string,
    dto: AdminEditCaregiverDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    const profileRecord = profile as unknown as Record<string, unknown>;
    const trackedFields = [
      'full_name',
      'gender',
      'age',
      'highest_qualification',
      'religion',
      'father_name',
      'father_phone',
      'current_address',
      'notes',
    ] as const;
    for (const field of trackedFields) {
      const nextValue = dto[field];
      if (nextValue === undefined) continue;
      if (profileRecord[field] !== nextValue) {
        before[field] = profileRecord[field];
        after[field] = nextValue;
      }
    }

    if (dto.languages !== undefined) {
      const previousLanguages = await this.languagesRepo.findByProfileId(profileId);
      const prevSorted = [...previousLanguages].sort();
      const nextSorted = [...dto.languages].sort();
      if (prevSorted.join(',') !== nextSorted.join(',')) {
        before.languages = prevSorted;
        after.languages = nextSorted;
      }
    }

    if (dto.preferred_cities !== undefined) {
      const previousCities = await this.preferredCitiesRepo.findByProfileId(profileId);
      const prevSorted = [...previousCities].sort();
      const nextSorted = [...dto.preferred_cities].sort();
      if (prevSorted.join(',') !== nextSorted.join(',')) {
        before.preferred_cities = prevSorted;
        after.preferred_cities = nextSorted;
      }
    }

    await this.db.withTransaction(async (client) => {
      if (dto.full_name !== undefined) {
        await this.usersRepo.updateFullName(profile.user_id, dto.full_name, client);
      }
      await this.profilesRepo.adminUpdate(
        profileId,
        {
          gender: dto.gender,
          age: dto.age,
          highest_qualification: dto.highest_qualification,
          religion: dto.religion,
          father_name: dto.father_name,
          father_phone: dto.father_phone,
          current_address: dto.current_address,
          notes: dto.notes,
        },
        client,
      );
      if (dto.languages !== undefined) {
        await this.languagesRepo.replaceForProfile(profileId, dto.languages, client);
      }
      if (dto.preferred_cities !== undefined) {
        await this.preferredCitiesRepo.replaceForProfile(profileId, dto.preferred_cities, client);
      }
    });

    if (Object.keys(after).length > 0) {
      await this.auditService.log({
        userId: adminId,
        targetUserId: profile.user_id,
        action: AuditAction.ADMIN_EDIT_PROFILE,
        entityType: 'caregiver_profiles',
        entityId: profileId,
        beforeValue: before,
        afterValue: after,
        ipAddress,
      });
    }

    return { message: 'Profile updated' };
  }

  async assignWorkTypes(
    profileId: string,
    adminId: string,
    dto: AssignWorkTypesDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const previous = await this.workTypesRepo.findByProfileId(profileId);
    await this.workTypesRepo.replaceForProfile(profileId, dto.work_types, adminId);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.WORK_TYPE_ASSIGNED,
      entityType: 'caregiver_work_types',
      entityId: profileId,
      beforeValue: { work_types: [...previous].sort() },
      afterValue: { work_types: [...dto.work_types].sort() },
      ipAddress,
    });

    return { message: 'Work types assigned', work_types: dto.work_types };
  }

  async assignServiceModes(
    profileId: string,
    adminId: string,
    dto: AssignServiceModesDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const previous = await this.serviceModesRepo.findByProfileId(profileId);
    await this.serviceModesRepo.replaceForProfile(profileId, dto.service_modes);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.SERVICE_MODE_ASSIGNED,
      entityType: 'caregiver_service_modes',
      entityId: profileId,
      beforeValue: { service_modes: [...previous].sort() },
      afterValue: { service_modes: [...dto.service_modes].sort() },
      ipAddress,
    });

    return { message: 'Service modes assigned', service_modes: dto.service_modes };
  }

  async updateSalary(
    profileId: string,
    adminId: string,
    dto: UpdateSalaryDto,
    ipAddress: string | null = null,
  ) {
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const previousSalary = profile.salary === null ? null : Number(profile.salary);
    await this.profilesRepo.updateSalary(profileId, dto.salary);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.ADMIN_EDIT_PROFILE,
      entityType: 'caregiver_profiles',
      entityId: profileId,
      beforeValue: { salary: previousSalary },
      afterValue: { salary: dto.salary },
      ipAddress,
    });

    return { message: 'Salary updated', salary: dto.salary };
  }

  /** Admin upload/replace of a caregiver's selfie. Overwrites any existing
   *  file at the same storage path (see UploadService.uploadFile upsert). */
  async uploadSelfie(
    profileId: string,
    adminId: string,
    file: Express.Multer.File | undefined,
    ipAddress: string | null = null,
  ) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');

    const hadFileBefore = profile.selfie_photo_url !== null;
    const ext = this.uploadService.extractExtension(file.originalname);
    const path = `${profileId}/selfie${ext ? `.${ext}` : ''}`;
    await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
    await this.profilesRepo.setSelfieUrl(profileId, path);

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.ADMIN_DOCUMENT_UPLOADED,
      entityType: 'caregiver_profiles',
      entityId: profileId,
      beforeValue: { document_type: 'selfie', had_file: hadFileBefore },
      afterValue: { document_type: 'selfie', had_file: true },
      ipAddress,
    });

    return { message: 'Selfie uploaded', file_path: `${Config.STORAGE_BUCKET}/${path}` };
  }

  /** Admin upload/replace of a caregiver's qualification/Aadhaar/other
   *  document. Mirrors CaregiverService.uploadDocument's path convention
   *  and the 3-document cap on "other" uploads. */
  async uploadDocument(
    profileId: string,
    adminId: string,
    dto: UploadDocumentDto,
    file: Express.Multer.File | undefined,
    ipAddress: string | null = null,
  ) {
    if (!file) throw new AppException('UPLOAD_001');
    const profile = await this.caregiversRepo.getDetailById(profileId);
    if (!profile) throw new AppException('PROFILE_019');
    const ext = this.uploadService.extractExtension(file.originalname);

    let path: string;
    let hadFileBefore: boolean;
    if (dto.document_type === DocumentType.QUALIFICATION) {
      hadFileBefore = profile.qualification_document_url !== null;
      path = `${profileId}/qualification${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.setQualificationDocumentUrl(profileId, path);
    } else if (dto.document_type === DocumentType.AADHAAR) {
      hadFileBefore = profile.aadhaar_document_url !== null;
      path = `${profileId}/aadhaar${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.setAadhaarDocumentUrl(profileId, path);
    } else {
      const existing = await this.profilesRepo.getOtherDocumentUrls(profileId);
      if (existing.length >= Validation.MAX_OTHER_DOCUMENTS) {
        throw new AppException('UPLOAD_003');
      }
      hadFileBefore = false;
      const index = existing.length + 1;
      path = `${profileId}/other_${index}${ext ? `.${ext}` : ''}`;
      await this.uploadService.uploadFile(Config.STORAGE_BUCKET, path, file.buffer, file.mimetype);
      await this.profilesRepo.appendOtherDocumentUrl(profileId, path);
    }

    await this.auditService.log({
      userId: adminId,
      targetUserId: profile.user_id,
      action: AuditAction.ADMIN_DOCUMENT_UPLOADED,
      entityType: 'caregiver_profiles',
      entityId: profileId,
      beforeValue: { document_type: dto.document_type, had_file: hadFileBefore },
      afterValue: { document_type: dto.document_type, had_file: true },
      ipAddress,
    });

    return {
      message: 'Document uploaded',
      document_type: dto.document_type,
      file_path: `${Config.STORAGE_BUCKET}/${path}`,
    };
  }
}
