-- ============================================
-- Reverting the per-app split from migration 068: NurseJobs (caregiver)
-- and NurseNow (patient/family + hospital/rehab) are no longer two
-- independently-shipped binaries — they are merged into a single
-- published app (JustHeal, apps/justheal-app) that builds as one APK/
-- bundle with one version number. The "force-upgrade/maintenance either
-- app independently of the other" premise from migration 068 no longer
-- holds: there is only one real installed app version to check, and only
-- the host's own (ex-NurseNow) splash screen actually runs this check
-- post-merge — the ported caregiver flow's own copy of the same check
-- became unreachable dead code (nothing navigates to its route anymore).
-- Collapsing app_min_versions back to one row per platform (its original
-- migration-031 shape) and app_maintenance to a single singleton row,
-- keeping the 'nursenow' rows' values since those are the ones that have
-- actually been live/enforced for every user since the merge.
-- ============================================

DELETE FROM app_min_versions WHERE app = 'nursejobs';
ALTER TABLE app_min_versions DROP CONSTRAINT app_min_versions_pkey;
ALTER TABLE app_min_versions DROP COLUMN app;
ALTER TABLE app_min_versions ADD CONSTRAINT app_min_versions_pkey PRIMARY KEY (platform);

DELETE FROM app_maintenance WHERE app = 'nursejobs';
ALTER TABLE app_maintenance DROP CONSTRAINT app_maintenance_pkey;
ALTER TABLE app_maintenance DROP COLUMN app;
ALTER TABLE app_maintenance ADD COLUMN id INT NOT NULL DEFAULT 1;
ALTER TABLE app_maintenance ADD CONSTRAINT app_maintenance_pkey PRIMARY KEY (id);
ALTER TABLE app_maintenance ADD CONSTRAINT app_maintenance_id_check CHECK (id = 1);
