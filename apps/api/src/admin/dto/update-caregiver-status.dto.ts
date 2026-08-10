import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { Validation, VerificationStatus } from '@vitacare/shared-constants';

/**
 * Admin override — deliberately unrestricted (no transition-matrix check):
 * admin can set ANY caregiver to ANY VerificationStatus directly, not just
 * the "normal flow" transitions (Start Review / Approve / Reject) that
 * admin-web's quick-action buttons cover. See admin.service.ts's
 * updateStatus() for the (few) field side-effects this still applies
 * (verified_at/verified_by on `available`, rejection_message on `rejected`).
 */
export class UpdateCaregiverStatusDto {
  @IsIn(Object.values(VerificationStatus), { message: 'ADMIN_001' })
  status!: VerificationStatus;

  @IsOptional()
  @IsString()
  @MaxLength(Validation.REJECTION_MESSAGE_MAX_LENGTH, { message: 'ADMIN_007' })
  rejection_message?: string | null;
}
