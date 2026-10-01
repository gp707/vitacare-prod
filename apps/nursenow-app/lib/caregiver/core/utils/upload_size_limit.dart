/// NurseJobs-specific: the Selfie photo and Aadhaar Card uploads are capped
/// tighter than the shared cross-app document limit (Validation.
/// fileMaxSizeBytes, still 10MB and still enforced by the backend as the
/// outer safety net) — these two are ordinary photos that rarely need to
/// be this large, and a tighter client-side cap here keeps a typical
/// upload fast even on a poor connection. Qualification Document and
/// Other Documents are unaffected — they keep the shared 10MB limit.
const photoAadhaarMaxSizeBytes = 4 * 1024 * 1024;
const photoAadhaarMaxSizeMb = 4;

/// Shown when a selfie or Aadhaar file is picked over [photoAadhaarMaxSizeBytes].
const photoAadhaarTooLargeMessage =
    'Your upload size is crossing the ${photoAadhaarMaxSizeMb}MB limit. Try reducing the file size, '
    'or tap the Help button above to contact us.';
