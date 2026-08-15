/// Mirrors packages/shared-constants/src/validation.ts.
class Validation {
  static final RegExp phoneRegex = RegExp(r'^\+91[6-9]\d{9}$');
  static final RegExp nameRegex = RegExp(r'^[a-zA-Z\s]+$');
  static const nameMaxLength = 100;
  static const codeLength = 4;
  static final RegExp codeRegex = RegExp(r'^\d{4}$');
  static const ageMin = 18;
  static const ageMax = 65;
  static const rejectionMessageMaxLength = 1000;
  static const fileMaxSizeBytes = 10 * 1024 * 1024;
  static const maxOtherDocuments = 3;
  static const paginationDefaultLimit = 20;
  static const paginationMaxLimit = 100;
  static const passwordMinLength = 6;
}
