import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface CaregiverDocumentVersionRecord {
  id: string;
  document_type: string;
  slot_index: number | null;
  path: string;
  uploaded_by: string | null;
  uploaded_by_name: string | null;
  uploaded_by_role: 'caregiver' | 'admin';
  created_at: Date;
}

export interface CaregiverDocumentVersionRow {
  id: string;
  profile_id: string;
  document_type: 'selfie' | 'qualification' | 'aadhaar' | 'other';
  slot_index: number | null;
  path: string;
}

/** Append-only ledger of every document ever uploaded for a caregiver —
 *  caregiver_profiles' own selfie_photo_url/qualification_document_url/
 *  aadhaar_document_url/other_document_urls columns still hold only the
 *  CURRENT path per slot; this table is the full history behind them, one
 *  row per upload, never updated or deleted. */
@Injectable()
export class CaregiverDocumentsRepository {
  constructor(private readonly db: DatabaseService) {}

  async recordVersion(
    profileId: string,
    documentType: 'selfie' | 'qualification' | 'aadhaar' | 'other',
    path: string,
    uploadedBy: string,
    uploadedByRole: 'caregiver' | 'admin',
    slotIndex: number | null = null,
  ): Promise<void> {
    await this.db.query(
      `INSERT INTO caregiver_documents (profile_id, document_type, slot_index, path, uploaded_by, uploaded_by_role)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [profileId, documentType, slotIndex, path, uploadedBy, uploadedByRole],
    );
  }

  /** Every version ever uploaded for this profile, newest first within
   *  each document type/slot. */
  async listByProfileId(profileId: string): Promise<CaregiverDocumentVersionRecord[]> {
    const result = await this.db.query<CaregiverDocumentVersionRecord>(
      `SELECT cd.id, cd.document_type, cd.slot_index, cd.path,
              cd.uploaded_by, u.full_name AS uploaded_by_name, cd.uploaded_by_role, cd.created_at
       FROM caregiver_documents cd
       LEFT JOIN users u ON u.id = cd.uploaded_by
       WHERE cd.profile_id = $1
       ORDER BY cd.document_type ASC, cd.slot_index ASC NULLS FIRST, cd.created_at DESC`,
      [profileId],
    );
    return result.rows;
  }

  async findById(id: string): Promise<CaregiverDocumentVersionRow | null> {
    const result = await this.db.query<CaregiverDocumentVersionRow>(
      `SELECT id, profile_id, document_type, slot_index, path FROM caregiver_documents WHERE id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  /** Permanent — used only by admin's superadmin-only "delete an old
   *  version" cleanup. Never called from the normal upload/replace flow. */
  async deleteById(id: string): Promise<void> {
    await this.db.query('DELETE FROM caregiver_documents WHERE id = $1', [id]);
  }
}
