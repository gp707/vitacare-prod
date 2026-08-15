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
  PROFILE_008: {
    status: 403,
    message: 'Advanced details not available. Phone call verification required.',
  },
  PROFILE_009: { status: 400, message: 'Terms and conditions must be accepted' },
  PROFILE_010: { status: 400, message: 'Invalid religion value' },
  PROFILE_012: { status: 400, message: 'At least one service mode is required' },
  PROFILE_013: { status: 400, message: 'Invalid service mode' },
  PROFILE_016: { status: 400, message: 'Code must be exactly 4 digits' },
  PROFILE_017: {
    status: 400,
    message: 'Aadhaar card not uploaded. Please upload it before submitting.',
  },
  PROFILE_018: { status: 400, message: 'Invalid qualification value' },
  PROFILE_019: { status: 404, message: 'Caregiver profile not found' },
  PROFILE_020: {
    status: 400,
    message: 'Name must contain only alphabetic characters and spaces',
  },
  PROFILE_021: { status: 400, message: 'FCM token is required' },
  PROFILE_022: { status: 400, message: 'At least one work type is required' },
  PROFILE_023: { status: 400, message: 'Invalid work type' },
  PROFILE_024: { status: 400, message: 'Salary must be zero or greater' },
  PROFILE_025: {
    status: 403,
    message: 'Advanced details must be submitted before editing them',
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
  ADMIN_002: {
    status: 400,
    message: 'Cannot mark as call verified. Current status is not pending_call.',
  },
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
  JOB_001: { status: 403, message: 'Cannot respond to jobs until your profile is verified' },
  JOB_002: { status: 400, message: 'Job is closed and no longer accepting responses' },
  JOB_003: { status: 400, message: 'Message is required when asking for more details' },
  JOB_004: { status: 400, message: 'Invalid response value' },
  JOB_005: { status: 400, message: 'Cannot send a reminder for a closed job' },

  // General errors
  GEN_001: { status: 400, message: 'Invalid request body' },
  GEN_002: { status: 404, message: 'Resource not found' },
  GEN_003: { status: 500, message: 'Internal server error' },
  GEN_004: { status: 429, message: 'Too many requests' },
  GEN_005: { status: 400, message: 'Invalid pagination parameters' },
};

export type ErrorCode = keyof typeof ErrorCatalog;
