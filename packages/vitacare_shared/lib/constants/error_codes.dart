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
    'PROFILE_009': 'Terms and conditions must be accepted',
    'PROFILE_010': 'Invalid religion value',
    'PROFILE_016': 'Code must be exactly 4 digits',
    'PROFILE_018': 'Invalid qualification value',
    'PROFILE_019': 'Caregiver profile not found',
    'PROFILE_020': 'Name must contain only alphabetic characters and spaces',
    'PROFILE_021': 'FCM token is required',
    'PROFILE_022': 'Cannot mark yourself available from your current status',

    // Upload
    'UPLOAD_001': 'File is required',
    'UPLOAD_002': 'File size exceeds 10MB limit',
    'UPLOAD_003': 'Maximum 3 additional documents allowed',
    'UPLOAD_004': 'Invalid document_type. Must be: qualification, aadhaar, or other',
    'UPLOAD_005': 'File upload failed. Please try again.',

    // Admin
    'ADMIN_001': 'Invalid status transition',
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
    'JOB_001': 'Cannot apply to jobs until your profile is verified',
    'JOB_002': 'Job is closed and no longer accepting applications',
    'JOB_004': 'Invalid application status value',
    'JOB_005': 'Cannot send a reminder for a closed job',
    'JOB_006': 'Application not found',
    'JOB_007': 'Application has already been decided',
    'JOB_008': 'No active accepted application found for this job',
    'JOB_009': 'You already have a requirement in progress',
    'JOB_010': 'Your account is blocked from posting new requirements',
    'JOB_011': 'Only a pending-review requirement can be rejected',
    'JOB_012': 'A reason is required when declining an applicant',
    'ORG_001': 'End date cannot be before start date',
    'ORG_002': 'Weekday values must be between 1 (Monday) and 7 (Sunday)',

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
