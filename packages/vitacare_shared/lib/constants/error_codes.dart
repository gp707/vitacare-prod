/// Mirrors packages/shared-constants/src/error-codes.ts (SPEC.md section 7).
/// Kept as a flat code -> message map; HTTP status is not needed on the client.
class ErrorCodes {
  static const Map<String, String> messages = {
    // Authentication
    'AUTH_001': 'Phone number is already registered',
    'AUTH_002': 'No account found with this phone number',
    'AUTH_003': 'Invalid email or password',
    'AUTH_004': 'Account is deactivated',
    'AUTH_005': 'Invalid or expired token',
    'AUTH_006': 'Invalid refresh token',
    'AUTH_007': 'Insufficient permissions',
    'AUTH_008': 'Invalid code',

    // Profile
    'PROFILE_001': 'Full name is required',
    'PROFILE_003': 'Invalid gender value',
    'PROFILE_004': 'Age must be between 18 and 65',
    'PROFILE_005': 'At least one language is required',
    'PROFILE_006': 'Invalid language value',
    'PROFILE_007': 'Invalid phone number format',
    'PROFILE_008':
        'Advanced details not available. Phone call verification required.',
    'PROFILE_009': 'Terms and conditions must be accepted',
    'PROFILE_010': 'Invalid religion value',
    'PROFILE_011': "Father's name is required",
    'PROFILE_012': 'At least one service mode is required',
    'PROFILE_013': 'Invalid service mode',
    'PROFILE_014': 'Current address is required',
    'PROFILE_015': 'Address must be under 500 characters',
    'PROFILE_016': 'Code must be exactly 4 digits',
    'PROFILE_017': 'Aadhaar card not uploaded. Please upload it before submitting.',
    'PROFILE_018': 'Invalid qualification value',
    'PROFILE_019': 'Caregiver profile not found',
    'PROFILE_020': 'Name must contain only alphabetic characters and spaces',
    'PROFILE_021': 'FCM token is required',
    'PROFILE_022': 'At least one work type is required',
    'PROFILE_023': 'Invalid work type',
    'PROFILE_024': 'Salary must be zero or greater',
    'PROFILE_025': 'Advanced details must be submitted before editing them',

    // Upload
    'UPLOAD_001': 'File is required',
    'UPLOAD_002': 'File size exceeds 10MB limit',
    'UPLOAD_003': 'Maximum 3 additional documents allowed',
    'UPLOAD_004': 'Invalid document_type. Must be: qualification, aadhaar, or other',
    'UPLOAD_005': 'File upload failed. Please try again.',

    // Admin
    'ADMIN_001': 'Invalid status transition',
    'ADMIN_002': 'Cannot mark as call verified. Current status is not pending_call.',
    'ADMIN_003': 'Admin with this email already exists',
    'ADMIN_004': 'Admin user not found',
    'ADMIN_005': 'Cannot deactivate your own account',
    'ADMIN_006': 'Cannot deactivate a super admin',
    'ADMIN_007': 'Rejection message must be under 1000 characters',
    'ADMIN_008': 'Invalid code format. Must be exactly 4 digits.',
    'ADMIN_009': 'This phone number is already registered to another account',
    'ADMIN_010': 'Invalid phone number format',
    'ADMIN_011': 'No pending edits to acknowledge',
    'ADMIN_012': 'Cannot change your own role',
    'ADMIN_013': 'Cannot demote the last super admin',

    // Jobs
    'JOB_001': 'Cannot respond to jobs until your profile is verified',
    'JOB_002': 'Job is closed and no longer accepting responses',
    'JOB_003': 'Message is required when asking for more details',
    'JOB_004': 'Invalid response value',
    'JOB_005': 'Cannot send a reminder for a closed job',

    // General
    'GEN_001': 'Invalid request body',
    'GEN_002': 'Resource not found',
    'GEN_003': 'Internal server error',
    'GEN_004': 'Too many requests',
    'GEN_005': 'Invalid pagination parameters',
  };

  /// Falls back to the server-provided message if the code isn't recognized locally.
  static String messageFor(String code, {String? fallback}) =>
      messages[code] ?? fallback ?? 'Something went wrong. Please try again.';
}
