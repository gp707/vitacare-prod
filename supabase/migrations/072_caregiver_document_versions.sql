-- Every selfie/qualification/Aadhaar/other-document upload is recorded as
-- its own permanent row here, in addition to caregiver_profiles' existing
-- selfie_photo_url/qualification_document_url/aadhaar_document_url/
-- other_document_urls columns (which keep pointing at the CURRENT version
-- only, unchanged). Re-uploading no longer overwrites the previous file in
-- storage either — see UploadService callers, which now build each new
-- path with a timestamp suffix instead of a fixed filename — so every row
-- here always resolves to a real, still-existing object in Supabase
-- Storage, letting admin view/download any past version, not just the
-- latest one.
CREATE TABLE caregiver_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  document_type VARCHAR(20) NOT NULL CHECK (document_type IN ('selfie', 'qualification', 'aadhaar', 'other')),
  -- Distinguishes which of the up-to-3 "other" document slots this version
  -- belongs to (1/2/3) — null for selfie/qualification/aadhaar, which each
  -- have exactly one slot.
  slot_index INTEGER,
  path TEXT NOT NULL,
  uploaded_by UUID REFERENCES users(id),
  uploaded_by_role VARCHAR(20) NOT NULL CHECK (uploaded_by_role IN ('caregiver', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_caregiver_documents_profile_id ON caregiver_documents(profile_id);
