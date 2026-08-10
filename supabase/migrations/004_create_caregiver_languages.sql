-- ============================================
-- CAREGIVER LANGUAGES TABLE
-- ============================================
CREATE TABLE caregiver_languages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  language VARCHAR(50) NOT NULL CHECK (language IN (
    'hindi', 'english', 'kannada', 'tamil', 'telugu', 'malayalam', 'bengali', 'gujarati', 'marathi'
  )),
  UNIQUE(profile_id, language)
);

CREATE INDEX idx_caregiver_languages_profile ON caregiver_languages(profile_id);
