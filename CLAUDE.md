# VitaCare — AI Development Context

## Project Overview

VitaCare is an in-home caregiver onboarding platform by VitaCasaHealth (vitacasahealth.in).
- **V1 scope:** Caregiver registration + admin verification. No booking, payments, or family features.
- **Monorepo:** All apps and shared packages in one repository.

## Architecture

| App | Path | Tech |
|-----|------|------|
| Backend API | `apps/api/` | NestJS 10.x, Node.js 20 LTS, TypeScript |
| Caregiver Mobile ("NurseJobs") | `apps/caregiver-app/` | Flutter 3.19+, Dart, Riverpod |
| Patient/Hospital Mobile ("NurseNow") | `apps/nursenow-app/` | Flutter 3.19+, Dart, Riverpod |
| Admin Web | `apps/admin-web/` | Flutter Web 3.19+, Dart, Riverpod |
| Shared Constants (TS) | `packages/shared-constants/` | TypeScript |
| Shared Models (Dart) | `packages/vitacare_shared/` | Pure Dart (no Flutter imports) |
| Shared UI Tokens | `packages/vitacare_ui/` | Flutter (colors, spacing, micro-widgets only) |

## Key Decisions

- **Auth:** Custom JWT for everyone. No Supabase Auth. bcrypt + jsonwebtoken. Access token TTL differs by app: caregiver-app tokens never expire (no `exp` claim — the mobile app has no re-login flow), admin-web tokens expire after `JWT_ACCESS_TOKEN_TTL` (default 6 months). Neither app currently uses the refresh-token flow (`POST /auth/refresh` exists server-side but no Dio interceptor calls it) — the access token alone governs session length.
- **Phone number is unique per app bucket, not globally** (migration 045, `users_phone_app_bucket_key` — a Postgres expression unique index, not a plain column constraint): NurseJobs (`role = caregiver`), NurseNow (`role IN (individual, organisation)`), and admin (`role IN (admin, super_admin)`) are three independent buckets. The same phone number can hold one account in each bucket at once — e.g. a person can register as a NurseJobs caregiver AND, separately, as a NurseNow individual with the same phone number. These are fully independent, unlinked accounts (separate `users` rows, separate profile rows, separate login PINs) that merely happen to share a phone number — no data is shared or merged between them. Registering a second account within the SAME bucket (e.g. a second caregiver account, or an organisation account when that phone already has an individual account — individual and organisation share the NurseNow bucket) still 409s with `AUTH_001`, unchanged. `UsersRepository.findByPhoneAndRoles(phone, roles)` is the role-scoped lookup used everywhere a phone is checked (registration dedup, self-service phone-change dedup, admin phone-change dedup) — the old global `findByPhone` was removed. `POST /auth/login/code` (`LoginCodeDto`) gained a required `app` field (`'nursejobs'` | `'nursenow'`, the `LoginApp` enum) so the backend knows which bucket to search — caregiver-app always sends `nursejobs`, nursenow-app always sends `nursenow` (it doesn't know ahead of login whether the phone registered as individual or organisation — that's still decoded from the JWT afterward, same as before). Login can never accidentally authenticate into the wrong bucket's account even if both accounts happen to share the same 4-digit PIN, since the role-scoped lookup runs before the PIN is even compared.
- **Human-friendly sequential display IDs** for organisations (`ORG-<n>`), NurseNow individuals/patients (`PAT-<n>`), and caregivers (`NUR-<n>`) — migration 046, one dedicated Postgres sequence per table (`organisation_profiles.org_number`, `individual_profiles.patient_number`, `caregiver_profiles.caregiver_number`), each starting at 500 (not 1). Same convention as `jobs.job_number`/`organisation_requirements.requirement_number`: the raw integer is what's stored and returned over the API (`org_number`/`patient_number`/`caregiver_number`, all nullable in API schemas only because older/edge-case responses may omit them, never actually null once a profile row exists); the `ORG-`/`PAT-`/`NUR-` prefix is applied purely at display time via `organisationDisplayId()`/`patientDisplayId()`/`caregiverDisplayId()` in `packages/vitacare_shared/lib/models/display_id.dart`, so all three Flutter apps render identical text. Shown in admin-web's Caregivers/Patients-Family/Rehab-Hospitals list tables (a leading "ID" column) and detail views, on a caregiver's own Profile screen (caregiver-app) and an individual/organisation's own Profile screen (nursenow-app), and on the applicant-profile view an individual/organisation sees when reviewing a caregiver's application (nursenow-app's `CaregiverProfileViewScreen`).
- **admin-web list-screen filters:** every admin-web list screen (Caregivers, Jobs — which also
  surfaces organisation requirements, merged into the same list, see "NurseNow" below —
  Patients/Family, Rehab/Hospitals) has a filter panel with a free-text `search` box
  that matches (via `ILIKE`) the entity's name/phone and its display id — e.g. searching "NUR-500"
  or just "500" on Caregivers matches via `('NUR-' || cp.caregiver_number::text) ILIKE '%...%'`,
  same pattern for jobs (`ADMIN-JOB-<n>`/`PAT-JOB-<n>`/raw `job_number`), organisation requirements
  (`ORG-JOB-<n>`), individuals (`PAT-<n>`), and organisations (`ORG-<n>`). Caregivers adds Gender
  (`cp.gender`) and Preferred City (`EXISTS` against `caregiver_preferred_cities`) dropdowns; Jobs
  already had Job Poster/City/Patient's Gender/Duty Time/Status/Language, `search` was the one gap.
  **Jobs' `search` additionally matches the posting individual's own display id** (`PAT-<n>`, via a
  `LEFT JOIN individual_profiles ip ON ip.user_id = j.posted_by` — `ip.patient_number` is null for
  admin-posted jobs, so has no effect on those) — this is deliberately the *poster's* identity, not
  the job's own id, letting admin find every job a specific patient/family account has ever posted
  (e.g. searching "PAT-501") in one search, not just one job by its own `PAT-JOB-<n>`.
  The merged Jobs screen's "Posted By" dropdown (All jobs/Hospital/Clinic/Rehab/Patients) narrows
  to organisation requirements of one organisation type (via `organisation_type`) or to individual-
  posted jobs (via `posted_by_role=individual`) — see "NurseNow" below. Patients/Family and Rehab/Hospitals had zero filter
  infrastructure at any layer (DTO/service/repository) before this — both now support `search` and
  a `block_status` filter (`active`/`job_posting_blocked`/`blocked`, derived from
  `users.is_active` + `is_job_posting_blocked`, not a stored column); Rehab/Hospitals also adds
  Organisation Type and City. Every new backend filter follows the existing
  `buildXWhereClause(filters): { clause, params }` convention (`admin-caregivers.repository.ts`,
  `jobs.repository.ts`) — for organisation-requirements/individuals/organisations, remember any
  filter referencing a joined table's columns (e.g. `op.organisation_type`) must be included in
  BOTH the list query's `JOIN` and the count query's `JOIN` — the count query was written as a
  separate SQL string in each of these repositories, and it's easy to add a join-dependent filter
  condition to the shared `WHERE` clause while only updating the list query's `FROM`/`JOIN`,
  which then 500s the count query at runtime (caught by e2e testing, not by unit tests, since unit
  tests mock the repository layer entirely).
- **Audit Logs target/entity display ids:** `AuditLogsRepository` resolves display-id-backing
  numbers for both sides of an entry, not just the job-resolution described above. For the
  **target** (`audit_logs.target_user_id`) it joins `users` (for `target.role`) plus all three of
  `caregiver_profiles`/`individual_profiles`/`organisation_profiles` on `user_id = target_user_id`
  — since a user has exactly one role, at most one of `target_caregiver_number`/
  `target_patient_number`/`target_org_number` is ever non-null, and `target_user_role` says which
  (or is null/`'admin'`/`'super_admin'` when there's no caregiver/individual/organisation display
  id to show). **`entity_type` is NOT a reliable signal for the target's role** — e.g. a caregiver
  applying to an organisation requirement logs `entity_type: 'organisation_requirement_applications'`
  with the caregiver as `target_user_id`, and `admin_notes`/`job_applications` entries have the
  same mismatch — always resolve via `target_user_id → users.role`, never via `entity_type`. For
  the **entity itself**, `organisation_requirements`/`organisation_requirement_applications`
  entries resolve to `requirement_number`/`requirement_id` the same two-hop way jobs resolve to
  `job_number`/`job_id` (direct for `organisation_requirements`, one hop via
  `.requirement_id` for `organisation_requirement_applications`) — note the FK column there is
  `requirement_id`, not `job_id` like `job_applications` uses. admin-web's Audit Logs screen
  renders the target's display id (`NUR-`/`PAT-`/`ORG-<n>`) above their name in the Target column,
  and the requirement's `ORG-JOB-<n>` in the (renamed) "Job / Requirement" column — unlike the job
  case, there's no click-to-open dialog for the requirement row yet, since no admin-web dialog
  currently opens an organisation requirement's detail from outside its own list screen.
- **Database:** Supabase PostgreSQL (used as a standard Postgres, no RLS for app tables).
- **Storage:** Supabase Storage with signed URLs (1hr expiry). Files at `{profile_id}/filename.ext`.
- **Realtime:** Supabase Realtime for admin dashboard only. Caregivers use FCM push.
- **Email:** Nodemailer + Gmail SMTP (vitacasahealthindia@gmail.com). Plain text only in V1.
- **No OTP:** Phone login has no OTP. Phone verified via office call.
- **Caregiver login:** Phone + 4-digit code, always. The code is set at registration and is required for every login from the first session onward. There is no phone-only login endpoint.
- **There is no separate "Advanced Details" step.** Everything is collected in one registration (`POST /auth/register`): basic info, religion, highest qualification, and terms acceptance, plus documents uploaded via their own endpoints immediately after (selfie and Aadhaar are mandatory; qualification document and up to 3 "other" documents are optional). Religion is required at registration and locked from self-edit afterward; highest_qualification, preferred_cities (optional at registration), preferred_duty_types, min_salary_per_day, min_salary_per_month, and documents all remain editable afterward via the single self-edit endpoint (`PATCH /caregiver/profile`) or document re-upload endpoints.
- **father_name, father_phone, current_address, and notes have been removed from the product entirely** — no longer collected, stored, or displayed anywhere (caregiver-app, admin-web, or the database).
- **Admin-assigned work types, service modes, and salary have been removed from the product entirely**, along with the two admin-notes rate fields (Rate — 24Hrs Live-In, Rate — 12Hrs PG) — no longer collected, stored, or displayed anywhere. `admin_notes` still has `internal_notes` and `availability_remarks`. `WorkType`/`ServiceMode`/`SalaryRanges` are gone too — a job posting is no longer built around a single "work type" category (see "Job/Application Flow" below).
- **Job/Application Flow:** Admin posts a job describing the care receiver's needs, grouped in the admin-web posting/edit form into two clearly labeled sections (the underlying `care_receivers` table/model keeps its original name — only these are UI display labels). **Only `age`/`gender`/`weight_kg` are hard-required on the care receiver** (plus `city`/`area`/`start_date` on the job itself — `area` was previously optional free text, now required; `start_date`, labeled "Preferred Start Date", was previously optional, now required — while the free-text `description` field moved the other way, from required to optional, see below); every other care-receiver field — `communication`, `feeding_type`, `has_medical_condition`, `toilet_assistance`, `requires_vital_monitoring` — is optional on the form and, left unselected (or submitted empty), is defaulted server-side (`CARE_RECEIVER_DEFAULTS` in `jobs.service.ts`) to a real, explicit value: `communication` → `verbal`, `feeding_type` → `oral_independent`, `has_medical_condition` → `false`, `toilet_assistance` → `[independent]`, `requires_vital_monitoring` → `false`. These defaults are persisted (not left null), so they show up identically to an explicit selection everywhere — caregiver-app's job card and admin-web's edit-prefill both just render whatever is stored, with no special "defaulted" handling needed. **"About Patient"** (age, gender, weight, communication, feeding, has-medical-condition + conditions, toilet assistance — multi-select, admin can pick more than one: `uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`others`/`independent` — and vital monitoring: Yes/No, if Yes multi-select which vitals: blood pressure/blood sugar/oxygen-SpO₂/temperature/pulse/other — this was previously split into a separate "About Patient Condition" section; that section no longer exists, everything lives under "About Patient" now — `mobility` has since been removed from the product entirely, see the Mobility enum entry below), and **"About Nurse/Caregiver Requirement"** (salary, "Hours Care Needed" — one of exactly 3 fixed shifts, see "Duty Type" below, no separately admin-entered start/end time — Frequency of Care (`daily`/`monthly`, required), "Preferred Start Date" (required), and soft caregiver preferences: language preference is **multi-select** (`languages`, a non-empty array — not a single value), gender and religion are single-select; preferred religion offers `hindu`/`muslim`/`christian` only — **`others` is excluded**, it remains valid for a caregiver's own religion at registration, just not offered as a job preference; preferred religion (and language) stay purely informational tags never used as a filter, but **preferred gender is enforced server-side** — `GET /caregiver/jobs` only returns jobs whose `preferred_gender` is unset (no preference) or matches the requesting caregiver's own `caregiver_profiles.gender`, so a caregiver never sees a job posted for the other gender; this filtering happens in `JobsRepository.listActiveForCaregiver`, not in the caregiver-app UI). Job Location (city, area — both required) is its own section above these two; the free-text `description` field (label shortened to "More details you want to share about patient" — previously required, now optional) sits below them. A `care_receivers` row is created 1:1 with each job (not an independently reusable/searchable entity yet — a future "Patient" app will eventually supply real care-receiver identity data; this only captures the care-needs description). **Every one of these details is visible to caregivers too** — `GET /caregiver/jobs` joins in the full `care_receiver` (not just `GET /admin/jobs/:id`), and caregiver-app's job card renders it under the same two section labels, so a caregiver sees the full patient/condition/requirement picture directly on the jobs list, no separate detail screen needed. Caregivers **apply** or **reject** (`POST /caregiver/jobs/:id/apply`) — there's no "ask for more details" option. Admin reviews applicants, contacts them outside the app, then **accepts** one via `PATCH /admin/jobs/:jobId/applications/:applicationId` — this is the offer confirmation, not a separate in-app caregiver acceptance step. Accepting closes the job (`status = 'closed'`, no more applications) and sets that caregiver's `verification_status` to `assigned`. Admin can later reject that same accepted application to reopen the job and set the caregiver back to `available`. Other still-`applied` applications on a job are left untouched when one gets accepted — not auto-rejected. Admin can view a job's full details and edit any field (via `PATCH /admin/jobs/:id`, same shape/validation as create) — same job id, existing applications untouched regardless of status (including one with an accepted/assigned applicant). If the job was `closed` when edited, saving the edit also **reposts** it: status flips back to `active` and the "New Job" push re-broadcasts to all caregivers; editing an already-`active` job does not resend that push. **Once accepted, the caregiver can see and contact whoever posted the job** — `GET /caregiver/jobs/assigned` includes `job_poster: { full_name, phone }`, the posting admin's contact info, per job. This is deliberately scoped to that one endpoint only — never on the browse list (`GET /caregiver/jobs`) — since admin contact info is only shared once there's an actual accepted engagement, not to every caregiver browsing jobs. Shown in two places in caregiver-app: always on the MyJobs tab (the durable historical record — one contact card per job), and also on the Profile tab but only while `verification_status` is currently `assigned` (Profile fetches `GET /caregiver/jobs/assigned` itself, gated on that status, so it doesn't keep showing a past job's poster(s) once the caregiver is available again). **A caregiver can be accepted onto more than one job at once** — nothing in the eligibility check (`available`/`assigned` are both apply-eligible) or in `decideApplication` prevents a second acceptance while already `assigned`. `GET /caregiver/jobs/assigned` therefore returns an **array**, not a single job/null — every job the caregiver currently holds an `accepted` or `completed` `job_applications` row for, oldest-decision-first by `updated_at`; this is the durable history the MyJobs tab renders (one card per job), so a completed job stays listed rather than disappearing. Each accepted job in MyJobs gets its own **"Mark Complete"** button, calling `POST /caregiver/jobs/:id/complete` (caregiver-only, no body) — this flips just that one `job_applications` row to a fourth status, `completed` (with a `completed_at` timestamp, mirroring `applied_at`/`accepted_at`/`rejected_at`), and only drops `caregiver_profiles.verification_status` back to `available` once **no other `accepted` applications remain**; if the caregiver still holds another active job, `verification_status` stays `assigned`. `JOB_008` covers every case where completion doesn't apply — never applied to that job, still `applied`, already `rejected`, or already `completed`. The job itself is never reopened by completion (stays `closed`). **The caregiver's own application (`GET /caregiver/jobs`'s `my_application`) carries the real per-transition timeline** (`applied_at`/`accepted_at`/`rejected_at`, each null until that transition happens), not just the bare current `status` — a caregiver's own self-decline and an admin un-accepting them both land on `status = 'rejected'` in the DB, and `decided_by_admin` (derived from `decided_by IS NOT NULL`) is what tells them apart; caregiver-app shows "Declined: <date>" for the former and "Declined by employer: <date>" for the latter, alongside "Applied: <date>" and "Accepted: <date>" (if it happened) — never a bare unqualified "You declined". **Admin-web gets the same timeline, plus who decided it**: each row in `GET /admin/jobs/:id`'s `applications` array carries `applied_at`/`accepted_at`/`rejected_at` and `decided_by_name` (the deciding admin's `full_name`, resolved via a `LEFT JOIN users` on `decided_by` — `null` while `status = 'applied'` or on a caregiver self-decline). The Job Applicants dialog renders this under each applicant as "Applied: <date>", "Accepted: <date> by <admin>", and/or "Declined by <admin>: <date>".
- **admin-web's Jobs list opens read-only by default, not straight into an editable form.** Tapping a job row (anywhere except its action buttons) opens `JobReadOnlyDetailDialog` — every field as plain text, grouped the same as the Post/Edit form (Job Location/Hours-Care-Needed/Frequency/Salary/etc., then About Patient) — with its own **Edit** button that hands off to the existing `_JobFormDialog` edit flow. The row's own explicit **Edit** `TextButton` still jumps straight into the editable form as a shortcut, unchanged; the read-only view is an additional entry point, not a replacement for it.
- **Job display id, salary, and apply-by urgency:** Every job has a display id shown at the top of the job card/row on admin-web, caregiver-app, and nursenow-app — `ADMIN-JOB-<n>` for an admin-posted job or `PAT-JOB-<n>` for a NurseNow individual/patient-posted job (migration 047), each a dedicated sequence starting at 500, backed by the nullable `jobs.admin_job_number`/`jobs.patient_job_number` columns (exactly one is set per row, mutually exclusive by who posted it — set at INSERT time via `JobsRepository.create`'s `posted_by_role` parameter). The original single shared `jobs.job_number` (SERIAL from 1, used for both posters alike) still exists and is still populated on every insert, but is **no longer displayed anywhere** — it's kept only as an internal fallback and for audit-log job resolution (`AuditLogsRepository` resolves and returns `admin_job_number`/`patient_job_number` alongside it, so the Audit Logs screen's job link stays consistent with whatever the job shows elsewhere). The shared `jobDisplayId(JobModel)` helper (`packages/vitacare_shared/lib/models/job_model.dart`) picks the right prefix so all three Flutter apps render identical text; an analogous `organisationJobDisplayId(OrganisationRequirementModel)` formats an organisation-posted requirement as `ORG-JOB-<n>` (reusing `organisation_requirements.requirement_number`, whose sequence was rebased to start at 500 in the same migration — no new column needed there since that table has only one possible poster type). Admin sets a single required `salary_amount` when posting or editing a job; its unit follows the job's `frequency_of_care` (₹/day for `daily`, ₹/month for `monthly`), and this dynamic unit is shown everywhere the figure appears — admin-web's form label and job list row, and caregiver-app's job card, which shows it highlighted prominently at the top. Every job also carries `posted_at` (starts equal to `created_at`, but is bumped to "now" only when a `closed` job is edited-and-reposted — a plain edit of an already-`active` job leaves it untouched) driving a caregiver-facing **3-day apply-by urgency window**: `posted_at + 3 days`, shown as "Posted: <date>" plus a days-left message ("X days left to apply" / "Last day..." / "Application window closed"). This is purely informational — it does not block applying, and the job itself is not auto-closed when the window passes; admin must still close (or let it be) manually.
- **Caregiver job search preferences — removed from the product entirely (NurseJobs only).** A caregiver
  could previously set `preferred_cities`, `preferred_duty_types` (backed by a `caregiver_preferred_duty_types`
  junction table), `min_salary_per_day`, and `min_salary_per_month` (both columns on `caregiver_profiles`),
  which dynamically filtered `GET /caregiver/jobs` down to matching jobs. All of this — the whole filtering
  feature, caregiver-app's `JobPreferencesScreen` (reached via a gear icon on the Jobs tab), the self-edit
  endpoint's acceptance of any of these fields, and `preferred_duty_types`/`min_salary_per_day`/
  `min_salary_per_month` themselves (`caregiver_preferred_duty_types` table dropped, the two columns
  dropped, migration 054) — is gone. Every caregiver now sees every active job (still narrowed by a job's
  own `preferred_gender` vs the caregiver's own gender — that's the employer's stated preference, not a
  caregiver "search preference", and was never part of this feature). **`preferred_cities` itself is NOT
  fully removed** — only the caregiver's own ability to set it (registration's Preferred City section and
  self-edit both dropped it; `EditProfileDto`/`RegisterDto` no longer accept it, whitelist-rejects with
  `GEN_001` if sent) and its use in job filtering. `caregiver_preferred_cities` the table, and admin's own
  ability to set it (`PUT /admin/caregivers/:id`) plus admin-web's Caregivers list filter/display, are
  untouched — an admin can still set a caregiver's preferred city, it's just informational now (never used
  to filter what jobs that caregiver sees), and it still shows on nursenow-app's `CaregiverProfileViewScreen`
  (relabeled from "Job Search Preferences" to "Preferred Cities" there, since duty type/salary no longer
  apply) since NurseNow's applicant-review flow is out of NurseJobs' scope.
- **Profile edits don't auto-reset status for `available`/`unavailable` caregivers**, with one exception: changing phone number or re-uploading Aadhaar is identity-sensitive and sends them back to `pending_call` (see transition matrix). Every other edit (age, languages, highest_qualification, preferred_cities, preferred_duty_types, min_salary_per_day, min_salary_per_month, login code/PIN, selfie/qualification/other document re-uploads) only flags `has_pending_edits = true` for admin review, status untouched. **For a `rejected` caregiver, this is different: any edit at all — not just identity-sensitive ones — automatically resubmits them** (sends status back to `pending_call`). There's no separate "resubmit" action; editing the flagged field(s) normally is the resubmission.
- **Caregivers cannot edit their own full_name or gender.** Both are locked from self-edit past registration — only admins can change them (via the admin edit endpoint). **Religion** follows the same rule: set once at registration, it's locked from the self-edit endpoint (`PATCH /caregiver/profile`) — only admins can change it from that point on. Every other field remains caregiver-editable via self-edit.
- **Force-upgrade:** admin-web has an "App Versions" screen (any admin, not just super_admin) where an admin sets a `min_version` (and optional `store_url`/`update_message`) per platform (`android`/`ios`) in the `app_min_versions` table (one row per platform, seeded at `1.0.0`). The caregiver app checks `GET /app-versions/check?platform=&version=` (public, no auth) on every cold launch — before the splash screen even loads the session, via `AppVersionRepository.checkForUpdate()` — and if its own build (`PackageInfo.version`) is below `min_version`, shows a full-screen, non-dismissible `UpdateRequiredScreen` with the admin's `update_message` (or a generic default) and an "Update Now" button linking to `store_url`; nothing else in the app loads until the caregiver updates. Platform is determined via `defaultTargetPlatform` (not `dart:io Platform`, which doesn't compile for the web dev target this app is also tested against) — anything other than iOS is treated as `android`. The version check is deliberately **fail-open**: any error (network down, backend unreachable, malformed response) is caught and treated as "no update needed," since a broken check must never be able to lock every caregiver out. admin-web itself has no equivalent gate — it's a web app that just needs a browser reload to pick up a new deploy (see Firebase Hosting cache note), not a store-distributed binary.

## NurseNow (Patient/Family + Hospital/Rehab)

A separate companion app, **NurseNow** (`apps/nursenow-app/`), lets patients/families and
hospitals/rehabs/clinics post care requirements and get matched against the same caregiver
pool NurseJobs (`apps/caregiver-app/`) already serves. It is a genuinely separate Flutter app
(own app-store listing, own registration/login) — not a merged "one app for everyone" build —
sharing the same backend (`apps/api`) and Postgres DB. **Both account types are now built:
Individual (patient/family), covered first below, and Organisation (hospital/rehab/clinic),
covered in its own subsection further down.** Organisation was deliberately built on
brand-new dedicated tables/codepath rather than reusing `jobs`/`care_receivers` — a
fundamentally different posting shape (no `care_receiver`, a "type of nurse" enum instead of
a qualification enum, accommodation/food/special-skills fields, many simultaneous postings
per org, no per-requirement city/area since it's inherited from the org's own registered
location) that didn't fit the Individual/admin jobs-table model.

### Individual (Patient/Family)

- **Individual accounts reuse the existing `jobs`/`care_receivers`/`job_applications` tables and
  the existing caregiver-app browse-and-apply flow.** A patient/family's approved requirement is
  a real row in `jobs` (`posted_by` = the individual's `user_id`, no role restriction there).
  Caregivers see and apply to it via the exact same `GET /caregiver/jobs` /
  `POST /caregiver/jobs/:id/apply` endpoints used for admin-posted jobs — no caregiver-app
  changes were needed. Matching reuses the same `caregiver_profiles.verification_status` state
  machine (acceptance flips a caregiver to `assigned`), identical to any other job.
- **Auth:** `individual` is a new `users.role` value, authenticating exactly like a caregiver —
  phone + 4-digit PIN (bcrypt `code_hash`), non-expiring JWT (no `exp` claim, same as
  caregiver-app). `POST /auth/register/individual` (`phone`, `full_name`, `code`) creates the
  `users` row plus a 1:1 `individual_profiles` row; `POST /auth/login/code` is shared with
  caregiver login (role-generalized check). No account-level admin approval gate — an individual
  can post a requirement immediately after registering.
- **Posting flow:** `POST /individual/requirements` takes the same shape as admin's job-posting
  form (About Patient + city/area/duty_type/start_date/languages/preferred_gender/
  preferred_religion) **except `frequency_of_care` and `salary_amount`**, which admin sets during
  approval — the requirement is created with `status: 'pending_review'` and both fields `null`
  (`jobs.frequency_of_care` is nullable for exactly this reason). An admin approves by editing
  the job with the full shape (same `PATCH /admin/jobs/:id` edit dialog admin already uses,
  supplying `frequency_of_care`/`salary_amount`) — this transitions `pending_review → active` and
  stamps `posted_at`, reusing the exact same repost/push-broadcast code path that already
  reactivates a `closed` job on edit. Admin can instead **reject** a `pending_review` job via
  `PATCH /admin/jobs/:id/reject` (`{ reason }`, admin/super_admin only) — sets `status: 'closed'`
  and `jobs.rejection_reason`, visible to the individual on their own requirement view; only
  valid from `pending_review` (`JOB_011` otherwise). The individual only sees
  `frequency_of_care`/`salary_amount` once approved. **An Individual account may have at most one
  "live" requirement at a time**, where "live" includes a not-yet-approved `pending_review` one —
  enforced server-side (`JOB_009`) via `JobsRepository.findLiveByPostedBy`.
- **Individual-side endpoints** (`@Roles(UserRole.INDIVIDUAL)`, `src/individual/`):
  `GET /individual/me`, `POST /individual/requirements`, `GET /individual/requirements`,
  `GET /individual/requirements/:id/applications`,
  `GET /individual/requirements/:jobId/applications/:applicationId/profile` (an applicant's full
  profile — ownership-checked both ways, the job must be this individual's own AND the
  application must actually belong to it — delegates to
  `CaregiverService.getApplicantProfile(profileId)`, which returns the caregiver's complete
  profile: email, signed Aadhaar/qualification/other-document URLs, and job-search preferences
  are all included, same as the caregiver's own self-view. An individual/organisation reviewing
  a caregiver who applied is meant to see their full details, including identity documents, before
  deciding. Exact same JSON shape as `GET /caregiver/profile`, so nursenow-app parses either one
  with the same `CaregiverProfileModel`.),
  `PATCH /individual/requirements/:jobId/applications/:applicationId` (accept/reject an
  applicant — ownership-checked, then delegates to the same `JobsService.decideApplication` admin
  uses), `PATCH /individual/profile/phone` / `PATCH /individual/profile/code` (self-service phone
  and 4-digit PIN change, reusing caregiver's `UpdatePhoneDto`/`UpdateCodeDto` — no re-review
  logic, since an individual account has no verification pipeline to send back for review).
  **Viewing a candidate's profile is scoped to the single candidate currently under forced
  one-at-a-time review** (`_ReviewingApplicantTile`'s "View Profile" button in
  `JobsPostedScreen` — see the applicant-review flow described further below); already-decided
  candidates in the read-only history below it don't get a profile link. "View Profile" (both
  here and on Organisation's equivalent) pushes `nursenow-app`'s shared
  `CaregiverProfileViewScreen` (`lib/features/caregiver_profile/`) — a read-only page showing the
  caregiver's full profile (photo, name, a "VitaCare-verified" badge if `available`/`assigned`,
  phone, email, age, gender, qualification, religion, languages as chips, Aadhaar/qualification/
  other-document links each opened via `url_launcher`, and job-search preferences — preferred
  cities, hours-care-needed, min. salary — when set), matching everything
  `CaregiverService.getApplicantProfile` sends over the wire.
  `GET /individual/requirements` returns the account's full requirement history (not just the
  current one), each with its `care_receiver` joined in, so a past requirement's full detail and
  its applicants (including who was accepted) stay visible after it closes — not just while live.
  **nursenow-app has a 2-tab bottom nav** (`NurseNowBottomNav`, mirroring NurseJobs'
  `CaregiverBottomNav`): **Profile** (`/profile` — identity, phone/PIN self-edit, Logout) and
  **Jobs Posted** (`/home` — `JobsPostedScreen`, the full requirement history described above,
  each card showing the full About Patient / About Nurse-Caregiver Requirement detail inline, an
  always-visible applicants list once a requirement leaves `pending_review` [so an accepted
  caregiver's name/phone stay visible after the job closes], and a "Post a Requirement" CTA that's
  shown whenever the account has **no live requirement** — i.e. none `pending_review` or
  `active` — not merely whenever the history list is non-empty, so posting again is always
  possible once the current one closes or is rejected).
- **Applicant review is a free list — every candidate's profile and phone number stay visible,
  regardless of who rejected whom, and a previously-rejected candidate can always be reconsidered.**
  The patient/family sees the total count up front ("N candidates applied in total") plus every
  applicant, whichever status they're in (`applied`/`accepted`/`rejected`/`completed`) — nothing is
  hidden or dropped from view once decided, including a candidate this account itself rejected, one
  the caregiver self-withdrew from (`rejected` with `decided_by IS NULL`), or one whose engagement
  the caregiver marked complete. **Only one candidate can be `accepted` at a time** —
  `JobsService.decideApplication` enforces this server-side (`JOB_016`, `apps/api/src/jobs/
  jobs.service.ts`, via `JobApplicationsRepository.findAcceptedForJob`) by blocking an accept on
  any application other than the currently-accepted one; while someone is accepted, every other
  candidate (including a previously-rejected one) loses its Accept action but keeps View Profile.
  Rejecting (undoing) the current acceptance reopens the job and frees the slot, at which point any
  other candidate — including one already `rejected` — can be accepted ("Accept Anyway" in
  nursenow-app's UI, `_ApplicantTile` in `jobs_posted_screen.dart`). This same accept-from-rejected
  path is also how a candidate the caregiver self-withdrew from can be accepted after all. The
  `JOB_016` guard lives in the shared `decideApplication` method, so it applies equally if admin's
  own accept-an-applicant flow is ever used the same way. **Rejecting an applicant requires a
  reason** — `job_applications.decline_reason` (added by
  migration 040), enforced server-side by `IndividualService.decideMyApplication` (`JOB_012` if
  missing/blank) rather than in the shared `DecideApplicationDto`/`JobsService.decideApplication`,
  so admin's own reject-an-applicant flow (admin-web) stays reason-optional — this rule is
  NurseNow-individual-specific, not a change to the admin flow. `DecideApplicationDto.reason` is
  optional at the DTO level for exactly that reason; nursenow-app's reject dialog keeps its own
  Confirm button disabled until non-empty text is entered, so the mandatory-reason rule is also
  enforced client-side before the request is even made.
- **Post a Requirement / Register forms use the same "always-tappable submit, highlight-and-scroll
  on invalid" pattern as admin-web's job-posting form** (see "Naming Conventions"/admin-web's
  `AdminJobsScreen` for the original): the submit button is never disabled; tapping it with a
  mandatory field empty flags every missing field red (with an inline message) and scrolls/focuses
  straight to the first invalid one, instead of showing one generic top-of-form error string.
  **caregiver-app's own `RegistrationScreen` (NurseJobs) uses the same pattern** — every mandatory
  field (full name, phone, 4-digit login code, age, languages, religion, highest qualification,
  selfie, Aadhaar, terms acceptance) gets a red border/label + inline error message simultaneously
  once Register is tapped with something missing, and the view scrolls/focuses to the first one in
  on-form order. Gender (has a default), preferred cities, qualification document, and other
  documents are optional and never flagged.
- **NurseNow Individual's Post/Edit Requirement forms are grouped into two clearly headed, boxed
  sections** (`PostRequirementScreen`/`EditRequirementScreen`, sharing a small `SectionBox` widget
  — a bordered `Container` with a bold, slightly-larger heading above its fields; every other
  field/label on the form keeps the same default text size/style, only the section heading differs)
  — replacing the old flat "About Patient"/"Care Location" heading pair with no visual grouping.
  **"Patient Details"**: Patient's Age, Patient's Gender, Patient's Weight, City, Area, Medical
  Condition (Care Location's fields — city/area — moved into this section rather than staying
  separate). **"Care Preferences"**: Hours Care Needed, Preferred Start Date, Toilet Assistance,
  Feeding/Medicine Assistance (the Feeding Type field, relabeled for this form only — admin-web's
  own form still labels it "Feeding"), Preferred Caregiver Gender, Language Preference, Preferred
  Caregiver Religion — this exact field order, matching the mandatory-field scroll-to-first-invalid
  order too. `EditRequirementScreen` additionally keeps its existing conditional **"Frequency &
  Salary"** section (only shown once the requirement has been approved at least once) as its own
  third `SectionBox`, unchanged in behavior. The free-text "More details you want to share about
  patient" field is removed from both forms entirely (NurseNow-specific — admin-web's own job
  posting form still has its own equivalent `description` field, untouched). **`JobsPostedScreen`'s
  own read-only "Show Full Details" expander mirrors this same grouping** — a `_DetailRow`
  label-above-value line per field (label small/secondary, value default body text), under the
  same "Patient Details"/"Care Preferences" headings in the same field order, replacing the old
  "About Patient"/"Patient Care Requirement" headings and their undifferentiated `Wrap` of bare
  `_Tag` chips (which made e.g. a lone "Male" chip ambiguous — patient's own gender, or a
  caregiver preference?). `_Tag` was removed as dead code once nothing referenced it anymore.
- **Admin blocking** (`individual_profiles.is_job_posting_blocked` + `block_reason`, or full
  lockout via the existing `users.is_active` + `AUTH_004`, both admin-entered-reason): admin-web's
  **"Patients/Family"** sidebar tab (`/patients-family`, any admin) lists every individual account
  via `GET /admin/individuals` and can block/unblock at either level
  (`PATCH /admin/individuals/:id/block` `{ level: 'job_posting' | 'full', reason }` /
  `.../unblock`). `job_posting` blocked (`JOB_010`) only stops *new* postings — an existing live
  requirement/its applications keep working, and login still succeeds. Full block (`is_active =
  false`) is a total login lockout (`AUTH_004`), same behavior as a deactivated admin/caregiver.
- Admin's own Jobs screen (`AdminJobsScreen`) surfaces NurseNow postings inline: a "Pending
  Review" badge on `pending_review` jobs, a "Posted by patient/family — <name>" label (via
  `GET /admin/jobs`'s joined `posted_by_role`/`posted_by_name`), an optional `posted_by_role`
  filter, and the Reject button described above — admin never needs a separate queue/screen to
  triage individual postings.
- **Admin edit + per-account audit history, both Patients/Family and Rehab/Hospitals**: tapping a
  row in either list screen (previously flat, no per-row navigation) opens a new single-page
  detail screen (`IndividualDetailScreen` / `OrganisationDetailScreen` — deliberately no tabs,
  unlike `CaregiverDetailScreen`, since neither `individual_profiles` nor `organisation_profiles`
  has document/notes depth) showing identity + status, an **Edit** toggle, and a scoped audit-
  history preview (`GET /admin/audit-logs?target_user_id=...`, same pattern as
  `CaregiverDetailScreen`'s Audit History tab) with a "View full audit log" link into the full
  `AuditLogsScreen` (`/audit-logs`, `initialTargetUserId` route argument — already generic, no
  router change needed for that part). `PUT /admin/individuals/:id`
  (`AdminEditIndividualDto`, `full_name` only — `individual_profiles` has no other editable
  columns) and `PUT /admin/organisations/:id` (`AdminEditOrganisationDto` — `full_name` [the
  contact person], `organisation_name`, `organisation_type`, `city`, `area`) both follow the exact
  same diff-only-what-changed-then-audit-log pattern as the caregiver `PUT /admin/caregivers/:id`
  (`AdminService.editProfile`), reusing `AuditAction.ADMIN_EDIT_PROFILE` and entity types
  `'individual_profiles'`/`'organisation_profiles'`. **For organisations, editing the contact
  person's name updates BOTH `users.full_name` (what the admin list/detail reads) AND
  `organisation_profiles.contact_person_name` (what the org's own `GET /organisation/me` self-view
  reads) — the two columns are otherwise independent copies of the same logical value, set together
  only once at registration; letting them drift apart on an admin edit would be a real bug, not
  just a display inconsistency.**

### Organisation (Hospital/Rehab/Clinic)

Entirely separate tables/codepath from Individual — `organisation_profiles`,
`organisation_requirements`, `organisation_requirement_applications` (migration 041) — mirroring
the *shape* of the jobs pipeline (same `pending_review → active → closed` status values, same
`applied/rejected/accepted/completed` application states, `decline_reason` from day one) without
reusing any of its tables.

- **Auth:** `organisation` is a new `users.role` value, authenticating exactly like caregiver/
  individual — phone + 4-digit PIN, non-expiring JWT. `POST /auth/register/organisation`
  (`phone`, `code`, `organisation_name`, `contact_person_name`, `organisation_type`, `city`,
  `area`) creates the `users` row plus a 1:1 `organisation_profiles` row. `city`/`area` are
  collected **once, at registration** — there is no per-requirement city/area, every requirement
  the org posts implicitly uses its own registered location (`city` here accepts the existing 7
  cities plus `'others'`, a separate org-scoped list validated at the DTO layer, not an
  extension of the shared `City` enum). No account-level approval gate, same as Individual.
- **Posting flow:** `POST /organisation/requirements` (`CreateOrganisationRequirementDto`) takes
  only `type_of_nurse`, `accommodation_provided`, `food_provided`, and optional `special_skills`
  — no care_receiver, no city/area/duty_type (inherited from the org's profile), no
  `frequency_of_care`/`salary_amount`/schedule (admin-set on approval, same null-until-
  approved pattern as an Individual's posting). Created with `status: 'pending_review'`.
  **Unlike Individual, there is no one-live-requirement limit** — an org can have many
  simultaneous postings, since a hospital/rehab genuinely needs to fill several openings at
  once; this was a deliberate scope difference, not an oversight.
- **Admin approves via the same "edit with full shape" pattern as Individual**:
  `PATCH /admin/organisation-requirements/:id` (`UpdateOrganisationRequirementDto`, requiring
  `type_of_nurse`/`frequency_of_care`/`salary_amount`/`accommodation_provided`/`food_provided`/
  `schedule_type`, transitions `pending_review` (or a `closed` requirement) to `active` and
  stamps `posted_at`. **`schedule_type` replaces the old single "Preferred Start Date" field for
  organisation requirements entirely** — admin picks exactly one of two modes: `date_range`
  (requires `start_date` + `end_date`, `end_date` must not be before `start_date` or the update
  400s with `ORG_001`) or `specific_days` (requires `schedule_repeat` + a non-empty `specific_days`
  array). **`schedule_repeat` is a second, nested choice that only applies within `specific_days`**
  — `weekly` (then `specific_days` holds ISO weekday numbers 1–7, Monday–Sunday, e.g. `[1, 3, 5]`
  for Mon/Wed/Fri, recurring every week; a value outside 1–7 400s with `ORG_002`) or `monthly`
  (then `specific_days` holds day-of-month numbers 1–31, e.g. `[3, 12, 20]`, recurring every
  month). admin-web's edit dialog shows this as a nested "Repeat" `SegmentedButton` (Weekly /
  Monthly) that only appears once `specific_days` is picked at the top level — Weekly reveals 7
  weekday `FilterChip`s, Monthly reveals a real month-grid calendar (`_MonthCalendarPicker`,
  weekday-aligned to the current real month purely for a familiar visual — only the tapped day
  NUMBER is captured, since the selection recurs every month regardless of which weekday that
  number falls on elsewhere) rather than a flat 1-31 chip list. Switching between Weekly and
  Monthly clears any already-picked days (the two numbering schemes are incompatible — day "5" of
  the month vs. weekday "5" = Friday). Every already-picked date/day/weekday in the edit dialog is
  marked with a green checkmark (`AppColors.success`) for visual confirmation once selected.
  Exactly one top-level mode's fields are required/persisted at a time — `@ValidateIf` in
  `UpdateOrganisationRequirementDto` enforces `start_date`/`end_date` only when
  `schedule_type === 'date_range'` and `schedule_repeat`/`specific_days` only when
  `schedule_type === 'specific_days'`; the unused mode's columns are stored `null`. This is
  enforced in `OrganisationRequirementsService.updateRequirement`/the DTO, not a DB constraint
  (the `organisation_requirements` table just has nullable `schedule_type`/`end_date`/
  `schedule_repeat`/`specific_days INTEGER[]` columns, migrations 043 and 044).
  **Caregiver-facing display reuses the same red blinking urgency badge** jobs use for "Preferred
  Start Date" (`BlinkingStartDateBadge`, generalized from a raw `startDate` param to a
  pre-formatted `label` param for exactly this reason) — showing `"<start> – <end>"` for a date
  range, `"Days: <n>, <n>, ..."` for monthly specific days, or `"Every: Mon, Wed, Fri"` for weekly
  specific days, via the shared `organisationScheduleLabel()` helper in
  `packages/vitacare_shared/lib/models/organisation_requirement_model.dart` so caregiver-app,
  nursenow-app, and admin-web all render identical text. Admin can instead **reject** via
  `PATCH /admin/organisation-requirements/:id/reject` (`{ reason }`, reusing the same
  `RejectJobDto` Individual uses) — sets `status: 'closed'` + `rejection_reason`, only valid from
  `pending_review`.
- **Organisation-side endpoints** (`@Roles(UserRole.ORGANISATION)`, `src/organisation/`):
  `GET /organisation/me`, `POST /organisation/requirements`, `GET /organisation/requirements`
  (full history, not just current), `GET /organisation/requirements/:id/applications`,
  `GET /organisation/requirements/:requirementId/applications/:applicationId/profile` (an
  applicant's full profile — same ownership-check-both-ways pattern and same
  `CaregiverService.getApplicantProfile` full-profile shape as Individual's equivalent above).
  Since Organisation's review is a free list, not forced one-at-a-time, **every** applicant
  gets a "View Profile" button in `RequirementsPostedScreen`'s `_ApplicantTile` — decided or
  not, unlike Individual which only exposes it for the one candidate currently under review.
  `PATCH /organisation/requirements/:requirementId/applications/:applicationId` (accept/reject,
  ownership-checked, delegates to `OrganisationRequirementsService.decideApplication` — the same
  method admin's own decide-application endpoint calls), plus
  `PATCH /organisation/profile/phone` / `PATCH /organisation/profile/code` self-service
  (reusing caregiver's `UpdatePhoneDto`/`UpdateCodeDto`, no re-review logic — same as
  Individual).
- **Applicant review is a free list with an optional reason, NOT the forced one-at-a-time/
  mandatory-reason flow Individual has.** That rule was requested specifically for the
  patient/family side; generalizing it to Organisation without being asked would have been
  scope creep, so `OrganisationRequirementsService`'s reject path stays reason-optional,
  matching admin's own applicant-decision UX. Documented here so the asymmetry between the two
  NurseNow account types reads as intentional, not inconsistent.
- **Caregiver-facing:** organisation requirements are shown **merged into the same Jobs / MyJobs
  tabs as admin/individual jobs** — `apps/caregiver-app`'s bottom nav stays at 3 tabs (Profile,
  Jobs, MyJobs), not 4. (An earlier iteration gave organisation requirements their own 4th
  "Organisation Openings" tab as a deliberate separate-section decision; that was reversed on
  explicit follow-up request — a caregiver should only have to check one place.) `JobsScreen`
  fetches both `GET /caregiver/jobs` and `GET /caregiver/organisation-requirements` and renders
  them in one list sorted by post date (newest first), each with its own card
  (`_JobCard`/`_RequirementCard` in `jobs_screen.dart`) — a job and a requirement have too
  little in common to unify into one card, so only the sort/merge wrapper (`_Listing`) is shared.
  `MyAssignmentScreen` (the MyJobs tab) does the same merge for
  `GET /caregiver/jobs/assigned` and `GET /caregiver/organisation-requirements/assigned`, sorted
  oldest-accepted-first, so an accepted organisation requirement is still visible and completable
  (`POST /caregiver/organisation-requirements/:id/complete`) without a dedicated screen. To make
  this merge possible, `GET /caregiver/organisation-requirements` gained a per-caregiver
  `my_application` join (previously absent — the tab existed but never showed "already applied"
  state) and `GET /caregiver/organisation-requirements/assigned` was reshaped from bare
  `organisation_requirement_applications` rows into full requirement records with an embedded
  `my_application` (mirroring `GET /caregiver/jobs`/`.../assigned`'s existing `JobModel`/
  `MyApplicationModel` shape exactly, via a new `OrganisationRequirementWithMyApplication`
  /`OrganisationRequirementAssignedRecord` repository return type) — this is a real backend
  response-shape change, not just a frontend rearrangement. Applying, accepting, and completing
  still hit the exact same organisation-specific endpoints and state machine as before (accepting
  an org requirement flips `caregiver_profiles.verification_status` to `assigned`, sharing the
  field with regular jobs — a caregiver already `assigned` to one can still be accepted onto the
  other, same as being accepted onto two regular jobs at once); only the caregiver-app UI and the
  two GET endpoints' response shapes changed.
- **nursenow-app:** registration branches on account type (Individual vs Organisation) on the
  same `RegistrationScreen`, revealing `organisation_name`/`organisation_type` (dropdown)/
  `city` (dropdown, incl. `others`)/`area` fields only for the Organisation branch, submitting
  via `AuthRepository.registerOrganisation(...)` instead of `register(...)`. Post-login, role is
  decoded client-side from the JWT (`core/jwt_decode.dart`'s `decodeJwtPayload()`, base64url
  decode of the JWT's middle segment — no signature verification, purely to pick a home route)
  since the shared `POST /auth/login/code` endpoint doesn't indicate role in its response body;
  decode failure falls back to Individual for backward compatibility. An Organisation session
  gets its own home route (`/org-home` → `RequirementsPostedScreen`, an always-postable list —
  no live-limit banner, unlike Individual's `JobsPostedScreen`) and posting screen
  (`/org-post-requirement` → `PostOrganisationRequirementScreen`, the "exclusive" org form:
  Type of Nurse dropdown, Accommodation/Food Yes-No toggles, optional Special Skills — no
  About Patient / Job Location sections at all, since those don't apply). Applicant review on
  this screen is the simple non-forced Accept/Reject described above, not Individual's forced
  one-at-a-time flow.
- **admin-web:** one new sidebar tab, **"Rehab/Hospitals"** (`/rehab-hospitals` →
  `OrganisationsListScreen`, mirrors `IndividualsListScreen` exactly: lists every organisation
  account via `GET /admin/organisations` with the same two block levers,
  `PATCH /admin/organisations/:id/block` `{ level: 'job_posting' | 'full', reason }` /
  `.../unblock`). **Organisation requirements themselves have no separate sidebar tab** — an
  earlier iteration gave them their own screen (`AdminOrganisationRequirementsScreen`,
  `/rehab-requirements`), deliberately not folded into `AdminJobsScreen` since
  organisation_requirements is a wholly separate table/model from jobs; that separation was
  reversed on explicit follow-up request — admin now has a **single "Jobs" tab** that fetches and
  merges `GET /admin/jobs` and `GET /admin/organisation-requirements` into one list, sorted by
  post date, each with its own row type (`_JobRow`/`RequirementRow` — too different in shape to
  render as one row, only the sort/merge wrapper is shared, same pattern as caregiver-app's own
  merged Jobs tab, see "Job/Application Flow" above). A **"Posted By"** dropdown (All jobs /
  Hospital / Clinic / Rehab / Patients) narrows the list to one poster type at a time: Hospital/
  Clinic/Rehab fetches only organisation requirements (filtered by `organisation_type`), skipping
  the jobs endpoint entirely; Patients fetches only jobs (filtered by `posted_by_role=individual`),
  skipping organisation requirements entirely; All jobs fetches and merges both, unfiltered by
  poster type. The two data shapes still keep separate dialogs — admin never *creates* an
  organisation requirement (the org posts its own), so "Post New Job" only ever produces a `jobs`
  row; a requirement row's own actions (Applicants — each applicant row gets its own **Profile**
  button, `Navigator.pushNamed('/caregiver-detail', arguments: application.profileId)`, the same
  admin-only full-detail screen a job's Applicants dialog links to — Reject, reason-required,
  pending_review only, and **Edit**, doubling as "Approve" from `pending_review`, collecting
  Frequency of Care/Salary and a required schedule via a `SegmentedButton` picking Date Range or
  Specific Days, Specific Days revealing a nested Weekly/Monthly `SegmentedButton` that in turn
  shows either 7 weekday chips or a real month-grid calendar, see "Organisation" above) are
  extracted into `apps/admin-web/lib/features/organisation_requirements/widgets/
  requirement_widgets.dart` (`RequirementRow`, `EditRequirementDialog`,
  `RequirementApplicantsDialog`, `RequirementReadOnlyDialog`) and reused by the Jobs screen
  alongside its own job-specific dialogs (`_JobFormDialog`, `JobDetailDialog`,
  `JobReadOnlyDetailDialog`). Tapping a requirement row opens the same read-only-detail-first,
  Edit-button-inside pattern as a job row.
- **Page refresh restores the actual page, not the app's home tab**: all three Flutter apps
  (admin-web, caregiver-app/NurseJobs, nursenow-app) capture
  `WidgetsBinding.instance.platformDispatcher.defaultRouteName` in `main()` **before** `runApp` —
  this reflects the real browser URL/hash (e.g. `#/jobs`) at load time, which `MaterialApp`'s own
  hardcoded `initialRoute: '/'` would otherwise silently discard (the app always enters via a
  fixed root/splash screen first, to run the auth check, and that splash screen used to always
  redirect to a fixed default — `/dashboard`, `routeForStatus()`, or `homeRoute` — once auth
  resolved, with zero awareness of what page the browser was actually on). The captured value is
  threaded down (`AdminWebApp`/`CaregiverApp`/`NurseNowApp` → `buildRoutes()` → `RootScreen`/
  `SplashScreen`, all via a plain `initialDeepLinkRoute` constructor parameter, not a Riverpod
  provider) and, once the session resolves to authenticated, is restored **instead of** the fixed
  default — but only if it's in that app's own hardcoded `_restorableRoutes` safe-list (kept in
  sync with `router.dart` by hand). Routes requiring an argument this bare URL can't supply
  (admin-web's `/caregiver-detail`, `/audit-logs`, `/individual-detail`, `/organisation-detail`,
  all needing a real id) are deliberately excluded from the safe-list and fall back to the fixed
  default, same as before this fix — there's no way to reconstruct a required argument from a
  hash-only URL with this simple named-route setup (no real deep-linking/path-parameter parsing).
  nursenow-app additionally guards against restoring an organisation-only route
  (`/org-home`/`/org-post-requirement`) for an individual session or vice versa. No URL strategy
  change was needed (`usePathUrlStrategy()` is still never called anywhere — all three apps stay
  on Flutter's default hash-based routing, e.g. `#/jobs`) — the fix is purely about not discarding
  the hash Flutter already had access to.

## Rate Card (Salary Guidance)

A single, admin-editable salary-guidance grid (`rate_card` table, migration 052 — a singleton
row, `id` fixed to 1 by a DB `CHECK`) shown behind a persistent green "Rate Card" pill button
(icon + visible text label — a bare `currency_rupee` icon alone read as unclear/ambiguous) in the
AppBar of every caregiver-app (NurseJobs) screen and every nursenow-app **Individual**
(patient/family) screen — **deliberately never shown to Organisation (hospital/rehab/clinic)
accounts**, since these guidelines are for individual hiring, not institutional bulk hiring.
Concretely, in nursenow-app the icon appears on `profile_screen.dart`/`jobs_posted_screen.dart`/
`post_requirement_screen.dart`/`edit_requirement_screen.dart` only — it's absent from
`post_organisation_requirement_screen.dart`/`requirements_posted_screen.dart` (Organisation-only)
and from the shared `caregiver_profile_view_screen.dart` (reachable by both account types when
reviewing an applicant) and from `login_screen.dart`/`registration_screen.dart`/`splash_screen.dart`
(role not yet known/no chrome). In caregiver-app it appears on every screen that has an AppBar
except `login_screen.dart` (which has no AppBar at all — a deliberately chrome-less auth screen,
same reason `WhatsAppHelpButton` skips it too), `splash_screen.dart`, and
`update_required_screen.dart` (a non-dismissible blocking screen).

- **Shape is fixed (3 columns x 3 rows), only the text is admin-editable.** `column_labels`/
  `row_labels` are always exactly 3 entries each; `cells[row][col]` a matching 3x3 grid — every
  label, cell, and the title are free-text strings, not structured amount+unit fields, since the
  source data mixes plain rates ("26000 pm/867 per day"), a range with a note ("35000-42000 pm
  (depending on years of experience)"), and a plain refusal ("Caregivers are not suggested") —
  forcing a rigid numeric shape would lose that. There's no add/remove-row/column UI — not
  requested, and the 3x3 shape matches the seeded "Companion care / Bedside Care / Critical Care"
  x "Caregivers / Nursing students-backlogs / Nurses" grid from the original ask.
- **Backend** (`apps/api/src/rate-card/`): `GET /rate-card` is public (no auth) — both apps fetch
  fresh on every icon tap, no caching/global state. `GET /admin/rate-card` (adds
  `updated_by_name`) and `PATCH /admin/rate-card` are `ADMIN`/`SUPER_ADMIN`-only, audit-logged via
  `AuditAction.RATE_CARD_UPDATED` (entityType `'rate_card'`, no `entityId` — `rate_card.id` is an
  `INT`, not a `UUID`, so it can't be put in `audit_logs.entity_id`; same pattern as
  `otp_auth_settings`, which also has a non-UUID PK). `RATE_001` covers a malformed `cells` shape
  (not exactly 3 rows of exactly 3 strings each) — checked in `RateCardService`, not via
  class-validator decorators, since there's no clean built-in decorator for a nested `string[][]`.
- **admin-web**: `/rate-card` screen (`features/rate_card/`), a single inline editable form (title
  field + a 3x3 `Table` of label/cell `TextField`s), not a list-of-dialogs like App Versions —
  there's only ever one row to edit. Reuses the shared `RateCardModel` (`packages/vitacare_shared`)
  for both the request body and (wrapped in `RateCardWithUpdater`) the admin GET response.
- **Mobile apps**: `RateCardButton` (`apps/*/lib/app/rate_card_button.dart`) is duplicated per app
  (not shared via `vitacare_ui`, which is restricted to colors/spacing/micro-widgets only, not
  full dialogs with network calls) — same duplication precedent as `WhatsAppHelpButton`. Tapping
  opens an `AlertDialog` rendering the fetched grid read-only; a failed fetch shows a friendly
  inline error rather than crashing or blocking anything, since this is purely informational.
  Both `RateCardButton` and `WhatsAppHelpButton` (both apps) are wrapped in a `Padding(right: 6)` —
  without it, whichever of the two rendered last in an AppBar's `actions` list sat flush against
  the screen's right edge, since both buttons' own internal padding was already trimmed to near
  zero to fit 3-action AppBars (RateCard + WhatsApp + Logout) without overflowing.

## Scope of Work

A single, admin-editable set of 3 cumulative bullet lists — **Companion Care**, **Bedside Care**
("Everything in Companion Care, plus…"), **Critical Care** ("Everything in Bedside Care,
plus…") — stored in the `scope_of_work` table (migration 055, a singleton row like `rate_card`).
Shown to caregivers (NurseJobs) via a per-job **"Scope of Work"** button on `JobDetailCard`
(`apps/caregiver-app/lib/features/jobs/widgets/job_detail_card.dart`, next to "Show details" —
shared by both the Jobs list and MyJobs, and only rendered when `job.careReceiver != null`), never
shown on Organisation-posted requirements (`_RequirementCard`), which have no `care_receiver` to
derive a tier from — same exclusion `RateCardButton` already applies to Organisation accounts, for
the same "these guidelines are for individual hiring, not institutional bulk hiring" reason.

- **The tier is derived, never manually picked.** `deriveCareTier(CareReceiverModel)`
  (`packages/vitacare_shared/lib/models/care_tier.dart`) reads a job's already-collected
  care-receiver fields and picks exactly one of `CareTier.companionCare`/`bedsideCare`/
  `criticalCare`, checked highest-tier-first: **Critical Care** if `toilet_assistance` includes
  `uses_catheter`, `feeding_type` is `tube_feeding`/`oral_and_tube`, `requires_vital_monitoring` is
  true, or `medical_conditions` includes `insulin_administration_support`/`injection_support`/
  `oxygen_support`/`cannula_care`/`catheter_care`; else **Bedside Care** if `toilet_assistance`
  includes `uses_diapers`/`uses_bed_pan`/`complete_toileting_assistance`/`others`, `feeding_type`
  is `oral_needs_assistance`, or `has_medical_condition` is true (any condition, including ones not
  in the critical list above); else **Companion Care** (the independent/baseline case). This
  mapping is a product judgment call documented in code comments right at the function, not
  something the backend enforces — reviewable in one place if the intended tiering changes.
  Neither `communication` nor `mobility` (removed entirely, see care_receivers history) factor
  into the rule. The popup shows only the derived tier's bullets, stacked cumulatively with every
  tier below it via `ScopeOfWorkModel.bulletsFor(tier)` — never the full 3-tier table.
- **Backend** (`apps/api/src/scope-of-work/`): mirrors `rate-card`'s exact shape — `GET
  /scope-of-work` is public (no auth, fetched fresh on every button tap); `GET
  /admin/scope-of-work` (adds `updated_by_name`) and `PATCH /admin/scope-of-work` are
  `ADMIN`/`SUPER_ADMIN`-only, audit-logged via `AuditAction.SCOPE_OF_WORK_UPDATED` (entityType
  `'scope_of_work'`, no `entityId`, same non-UUID-PK reasoning as `rate_card`). `SCOPE_001` covers
  an empty tier or a tier containing a blank/whitespace-only bullet — checked in
  `ScopeOfWorkService`, not via class-validator, since `@IsString({each: true})` alone doesn't
  reject blank strings.
- **admin-web**: `/scope-of-work` screen (`features/scope_of_work/`) — unlike Rate Card's fixed
  3x3 grid, each tier here is a **free-length bullet list**: every bullet is its own `TextField`
  with a delete button, plus an "Add bullet" button per tier section, since the 3 tiers have no
  fixed bullet count.
- **Visible in 3 places — caregiver-app, nursenow-app (Individual only), and admin-web — always
  the same derived tier for the same job**, since all 3 read the same `care_receiver` fields
  through the same `deriveCareTier` function and the same admin-editable content. Unlike
  `RateCardButton`/`WhatsAppHelpButton`, `ScopeOfWorkButton` is NOT an AppBar action in any app —
  it takes a `CareReceiverModel` constructor param and lives inline wherever a specific job's
  detail is shown, since which tier it opens depends on that one job:
  - **caregiver-app** (`apps/caregiver-app/lib/app/scope_of_work_button.dart`): inline on
    `JobDetailCard`, next to "Show details" — shared by the Jobs list and MyJobs.
  - **nursenow-app** (`apps/nursenow-app/lib/app/scope_of_work_button.dart`, own
    `ScopeOfWorkRepository`/`scopeOfWorkRepositoryProvider`, hitting the same public
    `GET /scope-of-work`): inline on `JobsPostedScreen`'s `_RequirementCard`, shown up front
    (not gated behind "Show Full Details") whenever the individual's own posted requirement has a
    `care_receiver` — which it always does once posted, `pending_review` or `active` alike. This
    is what lets "both sides see the same scope of work": an Individual's own posting reuses the
    exact same `jobs`/`care_receivers` rows a caregiver later sees, so the derivation input is
    byte-for-byte identical. Not shown on Organisation's `RequirementsPostedScreen` — organisation
    requirements have no `care_receiver` at all (see "Organisation" above).
  - **admin-web** (`apps/admin-web/lib/features/jobs/widgets/scope_of_work_button.dart` — a
    *separate* file from the mobile apps', since admin-web's own `ScopeOfWorkRepository`
    (`features/scope_of_work/data/`) hits the authenticated `GET /admin/scope-of-work` and returns
    a `ScopeOfWorkWithUpdater` wrapper, not a bare `ScopeOfWorkModel` — the button unwraps
    `.scopeOfWork` before calling `.bulletsFor(tier)`): a labeled row (matching every other
    `_DetailRow` in the dialog) at the bottom of `JobReadOnlyDetailDialog`'s "About Patient"
    section, read-only — an admin can see which tier a job derives to, never override it, since
    the tier is always computed from that job's own care_receiver, exactly like the other two apps.

## Naming Conventions (STRICT)

| Context | Convention | Example |
|---------|-----------|---------|
| Database tables | snake_case | `caregiver_profiles` |
| Database columns | snake_case | `verification_status` |
| API endpoints | kebab-case | `/admin/caregivers/:id/status` |
| API request/response fields | snake_case | `full_name` |
| NestJS files | kebab-case | `caregiver.controller.ts` |
| NestJS classes | PascalCase | `CaregiverController` |
| Flutter files | snake_case | `caregiver_profile_screen.dart` |
| Flutter classes | PascalCase | `CaregiverProfileScreen` |
| Flutter routes | kebab-case | `/pending-call` |
| Enums (DB values) | snake_case | `pending_call`, `24hrs_live_in` |
| Error codes | UPPER_SNAKE | `AUTH_001`, `PROFILE_005` |
| Shared widgets | Vita prefix | `VitaStatusBadge` |

## API Response Format (ALL endpoints)

```json
// Success
{ "success": true, "data": { ... }, "meta": { "page": 1, "limit": 20, "total": 45, "totalPages": 3 } }

// Error
{ "success": false, "error": { "code": "AUTH_001", "message": "Phone number is already registered" } }
```

## DO NOT Rules

### Backend (NestJS)
- Do NOT use Supabase Auth. All auth is custom JWT.
- Do NOT create database triggers or stored procedures. All logic in NestJS.
- Do NOT return raw database errors to clients.
- Do NOT include stack traces in production responses.
- Do NOT store Aadhaar numbers as text. Only store file paths.
- Do NOT expose admin notes to caregiver-facing endpoints.
- Do NOT hardcode env values. Always use ConfigService.
- Do NOT store refresh tokens or codes in plain text. Store bcrypt hash.
- Do NOT validate file MIME types. Accept any file type, enforce 10MB max only.
- Do NOT use the Supabase service role key in client apps.
- Do NOT auto-reset verification status on profile edit — EXCEPT changing phone or re-uploading Aadhaar (resets `available`/`unavailable` back to `pending_call`), and EXCEPT any edit at all while `rejected` (also resets to `pending_call` — auto-resubmit).
- Do NOT allow status transitions not in the transition matrix — EXCEPT via the admin status-override endpoint (`PATCH /admin/caregivers/:id/status`), which is deliberately unrestricted: admin can set any caregiver to any status from any current status. Caregiver-initiated and system-triggered transitions (phone/Aadhaar change, edit-while-rejected) still must follow the matrix below.
- Do NOT return more than 100 items per page.

### Flutter (Both Apps)
- Do NOT import Flutter in `packages/vitacare_shared`. Pure Dart only.
- Do NOT put layout widgets, buttons, or text fields in `packages/vitacare_ui`.
- Do NOT use `ImageSource.gallery` for selfie capture. Camera only.
- Do NOT build a full ThemeData in the shared UI package.
- Do NOT queue offline writes. All mutations require internet.
- Show bottom navigation at all times after registration. Caregivers can browse jobs even before approval (motivates onboarding). 3 tabs: Profile, Jobs (browse/apply), MyJobs (every job the caregiver currently holds or has completed, from `GET /caregiver/jobs/assigned` — a caregiver can be accepted onto more than one job at once, see "Job/Application Flow" below).
- There is no "Advanced Details" screen. All fields (including documents) are collected on the Registration screen itself; the caregiver's own profile is always reachable and editable at any status via one Edit Profile screen (`/profile/edit`) — a rejected caregiver edits the same way as anyone else, and the backend auto-resubmits them.

### General
- Do NOT add features beyond V1 scope (no booking, payments, messaging, AI).
- Do NOT add dark mode, i18n, rate limiting, HTML emails in V1.
- Do NOT use code generation (build_runner, json_serializable) in shared packages.
- Do NOT commit .env files.

## Verification Status Transitions

Only **5 statuses** exist: `pending_call`, `available`, `unavailable`, `assigned`, `rejected`. There is no `call_verified`, `pending_verification`, or `in_process` — those existed only to track progress through a multi-stage onboarding funnel (phone verification, then a separate "Advanced Details" submission, then document review) that no longer exists. Since every field (including documents) is collected in one registration, the office call and document review both happen while the caregiver sits in `pending_call`, and admin decides directly.

Admin has an unrestricted override (`PATCH /admin/caregivers/:id/status` accepts any of the 5 statuses below as a target, from any current status — no transition-matrix check). The matrix below documents the *normal* flow — what caregiver actions, system triggers, and admin-web's quick-action buttons (Approve/Reject) actually produce day to day:

```
pending_call → available                         (admin: approve — sets verified_at, green icon)
pending_call → rejected                           (admin: reject)
available → unavailable                           (caregiver OR admin: "not taking work right now")
unavailable → available                           (admin only: "ready for work again" — self-service removed, see notes)
available → assigned                              (admin: assign — ONLY from available, NOT unavailable)
assigned → available                              (caregiver: per-job "Mark Complete" in MyJobs, only once no other accepted jobs remain; or admin: unassign — work completed)
available → pending_call                          (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
unavailable → pending_call                        (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
rejected → pending_call                           (system: any caregiver edit at all — auto-resubmit, no separate "resubmit" action)
```

**Notes:**
- `available` = verified + taking work. Green icon. Can respond to jobs.
- `unavailable` = verified but NOT taking work. Green icon (still verified) but greyed out. Cannot respond to jobs, cannot be assigned.
- `assigned` = currently working at least one job — a caregiver can hold more than one accepted job at once (nothing blocks a second acceptance while already `assigned`). Caregiver self-unassigns per job, not globally: MyJobs' "Mark Complete" button on each accepted job (`POST /caregiver/jobs/:id/complete`, caregiver-only, no body) flips that one `job_applications` row to a new `completed` status (with a `completed_at` timestamp) and drops `verification_status` back to `available` only once no `accepted` applications remain — if others are still active, it stays `assigned`. `JOB_008` if there's no active accepted application for that job (never applied, still `applied`, already `rejected`, or already `completed`). Like the old global button, this deliberately does NOT touch the job itself (stays `closed`) — the application row becomes the historical record, now distinguishing `accepted` (active) from `completed` (finished) rather than leaving everything as `accepted` forever. Admin can still unassign directly via the status-override endpoint regardless of per-job state.
- **The caregiver-facing "Available for Jobs" button and its backend endpoint (`POST /caregiver/mark-available`)
  have been removed from the product entirely** (`PROFILE_022`, the `MarkAvailable`-related repository/service
  methods and route, and the button on caregiver-app's Profile tab are all gone — `CaregiverProfilesRepository.
  markAvailable` the *repository* method survives, since it's shared internal plumbing other flows still call,
  e.g. undoing a job acceptance or completing a job; only the caregiver-self-service HTTP surface is gone).
  `unavailable → available` is now admin-only, via the unrestricted status-override endpoint. This is
  unrelated to `assigned → available`, which was already a separate mechanism (MyJobs' per-job "Mark
  Complete", `POST /caregiver/jobs/:id/complete`) and is untouched by this removal.
- Daily push at 8 AM IST reminds `available`/`unavailable` caregivers to confirm status. No response = no change.

## Enum Values (Source of Truth)

### Languages
hindi, english, kannada, tamil, telugu, malayalam, bengali, gujarati, marathi

### Religion
hindu, muslim, christian, others

### Cities (preferred city for availability)
bangalore, mumbai, hyderabad, chennai, pune, delhi, gurgaon

### Qualifications
rn_above_2_years ("Registered Nurse above 2 years of experience"), rn_below_2_years ("Registered Nurse below 2 years experience"), registered_recently ("Registered Recently"), bsc_gnm_unregistered ("BSC / GNM Completed - Unregistered"), anm_student_backlog ("ANM/Nursing Student/ Backlog"), gda_non_nursing ("GDA / Non Nursing")

### Gender
male, female, other

### User Roles
super_admin, admin, caregiver, individual (NurseNow patient/family account — see "NurseNow" above), organisation (NurseNow hospital/rehab/clinic account — see "NurseNow" above)

### Job Status
pending_review (NurseNow individual posting awaiting admin approval — never set by admin's own postings, which go straight to `active`), active, closed. `organisation_requirements.status` reuses this exact same 3-value set independently (see "NurseNow" above) — it is not a foreign key into `jobs`, just the same enum shape.

### Organisation Type
hospital, rehab, clinic — set once at organisation registration (`POST /auth/register/organisation`), shown alongside the org's name everywhere admin-web lists it.

### Type of Nurse/Caregiver (organisation requirements only)
registered_nurse ("Registered Nurse"), nursing_completed ("Nursing Completed Nurses"), nursing_student ("Nursing Students"), auxiliary_nurse ("Auxiliary Nurses"), non_nursing_staff ("Non Nursing Staff"), paramedical_staff ("Paramedical Staff"), others ("Others"). Validated at the DTO layer (`@IsIn`), not a DB `CHECK`, so the list can be adjusted without a migration. Distinct from `Qualification` (a caregiver's own self-reported credential) — this is the category an organisation requests when posting a requirement.

### Schedule Type (organisation requirements only)
Set by admin on approval/edit of an organisation requirement, alongside Frequency of Care/Salary — **replaces the "Preferred Start Date" field entirely for organisation requirements** (regular VitaCare/admin jobs and Individual/NurseNow requirements still use the single `start_date` field, unchanged). Admin picks exactly one:
- `date_range` — "Date Range": requires `start_date` + `end_date` (`end_date` must not be before `start_date`, else `ORG_001`)
- `specific_days` — "Specific Days": requires a second nested choice, `schedule_repeat` (see below), plus a non-empty `specific_days` array whose valid range depends on that choice

Persisted on `organisation_requirements` (`schedule_type`, `end_date`, `schedule_repeat`, `specific_days INTEGER[]`, migrations 043 and 044); only the active mode's columns are populated, the other stays `null`. Shown to caregivers via the same red blinking urgency badge used for jobs' Preferred Start Date, with text from the shared `organisationScheduleLabel()` helper (`"<start> – <end>"`, `"Days: <n>, <n>, ..."`, or `"Every: Mon, Wed, Fri"`).

### Schedule Repeat (organisation requirements only, `schedule_type: specific_days` only)
A second, nested choice under `specific_days` — picks what `specific_days`' numbers mean:
- `weekly` — "Weekly": `specific_days` holds ISO weekday numbers (1=Monday..7=Sunday, e.g. `[1, 3, 5]` for Mon/Wed/Fri), recurring every week. A value outside 1–7 400s with `ORG_002`.
- `monthly` — "Monthly": `specific_days` holds day-of-month numbers (1–31, e.g. `[3, 12, 20]`), recurring every month regardless of what weekday that day falls on in a given month.

admin-web's edit dialog surfaces this as a nested "Repeat" `SegmentedButton` shown only once `specific_days` is picked at the top level: Weekly reveals 7 weekday `FilterChip`s (Mon–Sun); Monthly reveals a real weekday-aligned month-grid calendar (`_MonthCalendarPicker`, laid out against the current real month purely for a familiar visual — only the tapped day *number* is captured, since the selection recurs every month independent of which weekday it falls on elsewhere). Switching between Weekly and Monthly clears any already-picked values, since the two numbering schemes are incompatible. Every picked date/day/weekday across the dialog (date-range dates, weekday chips, calendar days) shows a green checkmark (`AppColors.success`) once selected, for visual confirmation.

### Job Application Status
applied, rejected, accepted, completed — `accepted` is admin-only (see "Job/Application Flow" below); a caregiver can only ever set `applied`/`rejected` on their own application via apply, and `completed` via the separate per-job complete endpoint (`accepted` → `completed` only, see "Job/Application Flow").

### Duty Type
Field labeled "Hours Care Needed" in the admin-web UI (underlying field/column name unchanged: `duty_type`). Exactly 3 fixed shifts — no "other", and no separately admin-entered start/end time; the shift's timing is implied by which one is picked (the backend derives and stores `start_time`/`end_time` from `duty_type`):
- `live_in` — "24Hrs - Live In" (no fixed start/end time)
- `day_duty` — "12Hrs Day Shift (8am to 8pm)"
- `night_duty` — "12Hrs Night Shift (8pm to 8am)"

### Frequency of Care
Required single-select on a job, alongside Duty Type/Hours Care Needed: `daily` ("Daily"), `monthly` ("Monthly"). Visible to caregivers on the job card same as every other requirement field.

### Mobility — removed from the product entirely
The old `walks_independently`/`walks_with_assistance`/`uses_walker`/`uses_wheelchair`/`bedridden`
enum and its backing `care_receivers.mobility` column (migration 053) no longer exist — not
collected, stored, or displayed anywhere (admin-web's job posting/edit form and read-only detail
view, caregiver-app's job card, nursenow-app's Post/Edit Requirement forms, or the API). Removed
alongside NurseNow's Post/Edit Requirement restructure into "Patient Details"/"Care Preferences"
sections (see "NurseNow" above) — CARE_RECEIVER_DEFAULTS in `jobs.service.ts` no longer has a
mobility entry.

### Communication
Exactly 3 options (`other_non_verbal` dropped):
- `verbal` — "Can Speak/Communicate"
- `difficulty_communicating` — "Can NOT Speak"
- `sign_language` — "Communicate via Sign Languages"

### Feeding Type
oral_independent, oral_needs_assistance, tube_feeding, oral_and_tube

### Medical Assistance — removed from the product entirely
The old "Medicine" multi-select (medication_reminders/medication_administration/insulin_administration/other_injections/other) and its backing `care_receivers.medical_assistance` column (migration 050) no longer exist — not collected, stored, or displayed anywhere (admin-web's job posting form, caregiver-app's job card, nursenow-app's requirement form, or the API). Superseded by the expanded Medical Condition list below, which now covers most of the same ground (BP, Oxygen support, Insulin administration support, Injection support, Cannula care, Catheter care, Nebulisation support).

### Medical Condition (multi-select)
cancer, stroke, brain_injury, dementia_alzheimers, parkinsons, heart_condition, kidney_disease_dialysis, diabetes, colostomy, paralysis, tb, bp, oxygen_support, insulin_administration_support, injection_support, cannula_care, catheter_care, nebulisation_support, other. When `other` is selected, admin-web reveals an optional free-text field ("Please describe the other condition") stored as `care_receivers.medical_condition_other`; sent alongside — not instead of — the selected values. Unconditionally optional server-side (no cross-field validation tying it to `other` being selected). Visible to caregivers on the job card as "Other condition: <text>". **nursenow-app's individual posting/edit forms make this field mandatory**, via a UI-only `none` sentinel (never sent to the backend — mutually exclusive with every real condition, same pattern as the Language Preference "No Preference" sentinel): it's the first chip, checked by default, and picking it clears `has_medical_condition`/`medical_conditions` entirely rather than sending an actual `none` value. Admin-web's own job posting form is unchanged — still an optional toggle, not mandatory.

### Toilet Assistance (multi-select)
uses_diapers, uses_bed_pan, uses_catheter, complete_toileting_assistance, others, independent. When `others` is selected, admin-web reveals an optional free-text field ("Please describe the other toilet assistance") stored as `care_receivers.toilet_assistance_other`; same pattern as `medical_condition_other` above (sent alongside the selected values, unconditionally optional, visible to caregivers as "Other toilet assistance: <text>").

### Vital Monitoring Type (multi-select)
blood_pressure, blood_sugar, oxygen_spo2, temperature, pulse, other

## File References

- Full requirements: `PRD.md`
- Technical spec: `SPEC.md`
- API contract: `docs/api-contract.yaml`
- Database ERD: `docs/database-erd.md`
- Test plan: `docs/test-plan.md`
- Environment setup: `docs/environment-setup.md`

## Sync Rule

Enums and validation constants exist in BOTH `packages/shared-constants` (TypeScript) and `packages/vitacare_shared` (Dart). When modifying an enum or constant, update BOTH packages in the same commit.
