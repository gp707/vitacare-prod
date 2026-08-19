export interface ErrorCatalogEntry {
  status: number;
  message: string;
}

export const ErrorCatalog: Record<string, ErrorCatalogEntry> = {
  // Authentication errors
  AUTH_001: { status: 409, message: 'Phone number is already registered' },
  AUTH_002: { status: 404, message: 'No account found with this phone number' },
  AUTH_003: { status: 401, message: 'Invalid email or password' },
  AUTH_004: { status: 401, message: 'Account is deactivated' },
  AUTH_005: { status: 401, message: 'Invalid or expired token' },
  AUTH_006: { status: 401, message: 'Invalid refresh token' },
  AUTH_007: { status: 403, message: 'Insufficient permissions' },
  AUTH_008: { status: 401, message: 'Invalid code' },

  // Profile errors
  PROFILE_001: { status: 400, message: 'Full name is required' },
  PROFILE_003: { status: 400, message: 'Invalid gender value' },
  PROFILE_004: { status: 400, message: 'Age must be between 18 and 65' },
  PROFILE_005: { status: 400, message: 'At least one language is required' },
  PROFILE_006: { status: 400, message: 'Invalid language value' },
  PROFILE_007: { status: 400, message: 'Invalid phone number format' },
  PROFILE_009: { status: 400, message: 'Terms and conditions must be accepted' },
  PROFILE_010: { status: 400, message: 'Invalid religion value' },
  PROFILE_016: { status: 400, message: 'Code must be exactly 4 digits' },
  PROFILE_018: { status: 400, message: 'Invalid qualification value' },
  PROFILE_019: { status: 404, message: 'Caregiver profile not found' },
  PROFILE_020: {
    status: 400,
    message: 'Name must contain only alphabetic characters and spaces',
  },
  PROFILE_021: { status: 400, message: 'FCM token is required' },
  PROFILE_022: {
    status: 400,
    message: 'Cannot mark yourself available from your current status',
  },

  // Upload errors
  UPLOAD_001: { status: 400, message: 'File is required' },
  UPLOAD_002: { status: 400, message: 'File size exceeds 10MB limit' },
  UPLOAD_003: { status: 400, message: 'Maximum 3 additional documents allowed' },
  UPLOAD_004: {
    status: 400,
    message: 'Invalid document_type. Must be: qualification, aadhaar, or other',
  },
  UPLOAD_005: { status: 500, message: 'File upload failed. Please try again.' },

  // Admin errors
  ADMIN_001: { status: 400, message: 'Invalid status transition' },
  ADMIN_003: { status: 409, message: 'Admin with this email already exists' },
  ADMIN_004: { status: 404, message: 'Admin user not found' },
  ADMIN_005: { status: 400, message: 'Cannot deactivate your own account' },
  ADMIN_006: { status: 400, message: 'Cannot deactivate a super admin' },
  ADMIN_007: { status: 400, message: 'Rejection message must be under 1000 characters' },
  ADMIN_008: { status: 400, message: 'Invalid code format. Must be exactly 4 digits.' },
  ADMIN_009: {
    status: 409,
    message: 'This phone number is already registered to another account',
  },
  ADMIN_010: { status: 400, message: 'Invalid phone number format' },
  ADMIN_011: { status: 400, message: 'No pending edits to acknowledge' },
  ADMIN_012: { status: 400, message: 'Cannot change your own role' },
  ADMIN_013: { status: 400, message: 'Cannot demote the last super admin' },

  // Job errors
  JOB_001: { status: 403, message: 'Cannot apply to jobs until your profile is verified' },
  JOB_002: { status: 400, message: 'Job is closed and no longer accepting applications' },
  JOB_004: { status: 400, message: 'Invalid application status value' },
  JOB_005: { status: 400, message: 'Cannot send a reminder for a closed job' },
  JOB_006: { status: 404, message: 'Application not found' },
  JOB_007: { status: 400, message: 'Application has already been decided' },
  JOB_008: { status: 400, message: 'No active accepted application found for this job' },
  JOB_009: { status: 400, message: 'You already have a requirement in progress' },
  JOB_010: { status: 403, message: 'Your account is blocked from posting new requirements' },
  JOB_011: { status: 400, message: 'Only a pending-review requirement can be rejected' },
  JOB_012: { status: 400, message: 'A reason is required when declining an applicant' },

  // Organisation errors (NurseNow)
  ORG_001: { status: 400, message: 'End date cannot be before start date' },
  ORG_002: { status: 400, message: 'Weekday values must be between 1 (Monday) and 7 (Sunday)' },

  // General errors
  GEN_001: { status: 400, message: 'Invalid request body' },
  GEN_002: { status: 404, message: 'Resource not found' },
  GEN_003: { status: 500, message: 'Internal server error' },
  GEN_004: { status: 429, message: 'Too many requests' },
  GEN_005: { status: 400, message: 'Invalid pagination parameters' },
};

export type ErrorCode = keyof typeof ErrorCatalog;
