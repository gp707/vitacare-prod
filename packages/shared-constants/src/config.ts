export const Config = {
  BCRYPT_SALT_ROUNDS: 10,
  // Admin web only — caregiver-app access tokens never expire.
  JWT_ACCESS_TOKEN_TTL_SECONDS: 15552000,
  JWT_REFRESH_TOKEN_TTL_SECONDS: 2592000,
  STORAGE_BUCKET: 'caregiver-documents',
  SIGNED_URL_EXPIRY_SECONDS: 3600,
  API_VERSION_PREFIX: 'v1',
} as const;
