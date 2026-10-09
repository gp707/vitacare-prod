# VitaCare — AI Development Context

## Project Overview

VitaCare is an in-home caregiver onboarding platform by VitaCasaHealth (vitacasahealth.in).
- **V1 scope:** Caregiver registration + admin verification. No booking, payments, or family features.
- **Monorepo:** All apps and shared packages in one repository.

## Architecture

| App | Path | Tech |
|-----|------|------|
| Backend API | `apps/api/` | NestJS 10.x, Node.js 20 LTS, TypeScript |
| Caregiver Mobile ("NurseJobs") | `apps/justheal-app/lib/caregiver/` | Flutter 3.19+, Dart, Riverpod |
| Patient/Hospital Mobile ("NurseNow" internally, published as **JustHeal**) | `apps/justheal-app/lib/patient_hospital/` | Flutter 3.19+, Dart, Riverpod |
| Admin Web | `apps/admin-web/` | Flutter Web 3.19+, Dart, Riverpod |
| Shared Constants (TS) | `packages/shared-constants/` | TypeScript |
| Shared Models (Dart) | `packages/vitacare_shared/` | Pure Dart (no Flutter imports) |
| Shared UI Tokens | `packages/vitacare_ui/` | Flutter (colors, spacing, micro-widgets only) |

**Both mobile rows above are one single published binary** (`apps/justheal-app`, published
to the app stores as **JustHeal** — see "NurseNow" below for the merge history). The old
standalone `apps/caregiver-app` has been deleted (it was a now-superseded duplicate of
`apps/justheal-app/lib/caregiver/`, kept around only until the merged flow was verified).
Elsewhere in this doc, **"caregiver-app"/"NurseJobs"** and **"nursenow-app"/"NurseNow"**
continue to be used as prose shorthand for these two internal code trees
(`apps/justheal-app/lib/caregiver/` and `apps/justheal-app/lib/patient_hospital/`
respectively) — treat them as names for "the caregiver-facing part" / "the patient/hospital-
facing part" of the one JustHeal app, not as references to separate directories or binaries.

## Key Decisions

- **Auth:** Custom JWT for everyone. No Supabase Auth. bcrypt + jsonwebtoken. Access token TTL differs by app: caregiver-app tokens never expire (no `exp` claim — the mobile app has no re-login flow), admin-web tokens expire after `JWT_ACCESS_TOKEN_TTL` (default 6 months). Neither app currently uses the refresh-token flow (`POST /auth/refresh` exists server-side but no Dio interceptor calls it) — the access token alone governs session length.
- **Phone number is now globally unique across every registration-facing role** (caregiver, individual, organisation) — a reversal of the original migration-045 design (below), driven by JustHeal merging NurseJobs (caregiver) and NurseNow (individual/organisation) into a single binary with one shared login screen (see "NurseNow"/JustHeal merge notes): since that one login screen now has to try both account kinds for the same phone number, a phone can no longer legitimately belong to more than one. `UsersRepository.findByPhoneAnyRole(phone)` (no role filter, unlike `findByPhoneAndRoles`) is called in `register`/`registerIndividual`/`registerOrganisation` immediately after the existing same-bucket `findByPhoneAndRoles` check passes — any row it finds is therefore guaranteed to be a different role, and registration 409s with the new `AUTH_016` (distinct from `AUTH_001`, which still covers a second registration attempt *within* the same bucket, e.g. a second caregiver account), with a message naming the existing role (e.g. "This phone number is already registered as a patient/family account. Each phone number can only be used for one account."). This is a forward-only validation added at registration time — any pre-existing dual-registered accounts from before this change are left alone, not retroactively merged or deleted. **The original "unique per app bucket, not globally" design is still what's documented below and still governs *login* routing** (migration 045, `users_phone_app_bucket_key`, the `findByPhoneAndRoles`/`LoginApp`-scoped lookup, and the bucket concept itself) — only the *registration* dedup policy changed; nothing about how an already-existing dual-bucket account logs in was touched. NurseJobs (`role = caregiver`), NurseNow (`role IN (individual, organisation)`), and admin (`role IN (admin, super_admin)`) are three independent buckets. Historically the same phone number could hold one account in each bucket at once — e.g. a person could register as a NurseJobs caregiver AND, separately, as a NurseNow individual with the same phone number — fully independent, unlinked accounts (separate `users` rows, separate profile rows, separate login PINs) that merely happened to share a phone number, no data shared or merged between them; new registrations can no longer create this situation, but the index itself (and any rows it already permitted) remain. Registering a second account within the SAME bucket (e.g. a second caregiver account, or an organisation account when that phone already has an individual account — individual and organisation share the NurseNow bucket) still 409s with `AUTH_001`, unchanged. `UsersRepository.findByPhoneAndRoles(phone, roles)` is the role-scoped lookup used everywhere a phone is checked (registration dedup, self-service phone-change dedup, admin phone-change dedup) — the old global `findByPhone` was removed. `POST /auth/login/code` (`LoginCodeDto`) gained a required `app` field (`'nursejobs'` | `'nursenow'`, the `LoginApp` enum) so the backend knows which bucket to search — caregiver-app always sends `nursejobs`, nursenow-app always sends `nursenow` (it doesn't know ahead of login whether the phone registered as individual or organisation — that's still decoded from the JWT afterward, same as before). Login can never accidentally authenticate into the wrong bucket's account even if both accounts happen to share the same 4-digit PIN, since the role-scoped lookup runs before the PIN is even compared. **JustHeal's own login screen now tries both buckets in sequence** — see the merge/unified-login notes under "NurseNow" — relying on the new global registration uniqueness to guarantee at most one of the two attempts can ever succeed. **Known gap**: the fallback (`_tryCaregiverLogin` in `lib/patient_hospital/features/auth/screens/login_screen.dart`) only covers the PIN-based path — if NurseNow's OTP mode is on (PIN fields hidden) while NurseJobs stays on PIN mode, a caregiver landing on this shared screen has no fallback into caregiver's own PIN login from the OTP flow; they'd still need to reach `/caregiver/login` directly (e.g. via "Caregivers Registration" → "Already registered? Login"). Not fixed — flagged as a known limitation rather than built out, since it's an edge case only reachable if an admin deliberately sets the two apps' OTP modes differently (see "Login Settings (OTP mode) is the one exception that stayed per-app" above).
- **Human-friendly sequential display IDs** for organisations (`ORG-<n>`), NurseNow individuals/patients (`PAT-<n>`), and caregivers (`NUR-<n>`) — migration 046, one dedicated Postgres sequence per table (`organisation_profiles.org_number`, `individual_profiles.patient_number`, `caregiver_profiles.caregiver_number`), each starting at 500 (not 1). Same convention as `jobs.admin_job_number`/`jobs.patient_job_number`/`organisation_requirements.requirement_number`: the raw integer is what's stored and returned over the API (`org_number`/`patient_number`/`caregiver_number`, all nullable in API schemas only because older/edge-case responses may omit them, never actually null once a profile row exists); the `ORG-`/`PAT-`/`NUR-` prefix is applied purely at display time via `organisationDisplayId()`/`patientDisplayId()`/`caregiverDisplayId()` in `packages/vitacare_shared/lib/models/display_id.dart`, so all three Flutter apps render identical text. Shown in admin-web's Caregivers/Patients-Family/Rehab-Hospitals list tables (a leading "ID" column) and detail views, on a caregiver's own Profile screen (caregiver-app) and an individual/organisation's own Profile screen (nursenow-app), and on the applicant-profile view an individual/organisation sees when reviewing a caregiver's application (nursenow-app's `CaregiverProfileViewScreen`).
- **admin-web list-screen filters:** every admin-web list screen (Caregivers, Jobs — which also
  surfaces organisation requirements, merged into the same list, see "NurseNow" below —
  Patients/Family, Rehab/Hospitals) has a filter panel with a free-text `search` box
  that matches (via `ILIKE`) the entity's name/phone and its display id — e.g. searching "NUR-500"
  or just "500" on Caregivers matches via `('NUR-' || cp.caregiver_number::text) ILIKE '%...%'`,
  same pattern for jobs (`ADMIN-JOB-<n>`/`PAT-JOB-<n>`), organisation requirements
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
  `admin_job_number`/`patient_job_number`/`job_id` (direct for `organisation_requirements`, one hop via
  `.requirement_id` for `organisation_requirement_applications`) — note the FK column there is
  `requirement_id`, not `job_id` like `job_applications` uses. admin-web's Audit Logs screen
  renders the target's display id (`NUR-`/`PAT-`/`ORG-<n>`) above their name in the Target column,
  and the requirement's `ORG-JOB-<n>` in the (renamed) "Job / Requirement" column — unlike the job
  case, there's no click-to-open dialog for the requirement row yet, since no admin-web dialog
  currently opens an organisation requirement's detail from outside its own list screen.
- **Database:** Supabase PostgreSQL (used as a standard Postgres, no RLS for app tables).
- **Storage:** Supabase Storage with signed URLs (1hr expiry). Files at `{profile_id}/filename.ext`.
- **Realtime:** Supabase Realtime for admin dashboard only. Caregivers use FCM push — as of the
  Admin Push Notifications feature (see its own section below), individual/organisation accounts
  now register an FCM token too, so they can receive an admin-composed push same as caregivers.
- **Email:** Nodemailer + Gmail SMTP (vitacasahealthindia@gmail.com). Plain text only in V1.
- **No OTP:** Phone login has no OTP. Phone verified via office call.
- **Caregiver login:** Phone + 4-digit code, always. The code is set at registration and is required for every login from the first session onward. There is no phone-only login endpoint.
- **There is no separate "Advanced Details" step.** Everything is collected in one registration (`POST /auth/register`): basic info, religion, highest qualification, and terms acceptance, plus documents uploaded via their own endpoints immediately after (selfie and Aadhaar are mandatory; qualification document and up to 3 "other" documents are optional). Religion is required at registration and locked from self-edit afterward; highest_qualification, preferred_cities (optional at registration), preferred_duty_types, min_salary_per_day, min_salary_per_month, and documents all remain editable afterward via the single self-edit endpoint (`PATCH /caregiver/profile`) or document re-upload endpoints.
- **father_name, father_phone, current_address, and notes have been removed from the product entirely** — no longer collected, stored, or displayed anywhere (caregiver-app, admin-web, or the database).
- **Admin-assigned work types, service modes, and salary have been removed from the product entirely**, along with the two admin-notes rate fields (Rate — 24Hrs Live-In, Rate — 12Hrs PG) — no longer collected, stored, or displayed anywhere. `admin_notes` still has `internal_notes` and `availability_remarks`. `WorkType`/`ServiceMode`/`SalaryRanges` are gone too — a job posting is no longer built around a single "work type" category (see "Job/Application Flow" below).
- **Job/Application Flow:** Admin posts a job describing the care receiver's needs, grouped in the admin-web posting/edit form into two clearly labeled sections (the underlying `care_receivers` table/model keeps its original name — only these are UI display labels). **Only `age`/`gender`/`weight_kg` are hard-required on the care receiver** (plus `city`/`area`/`start_date` on the job itself — `area` was previously optional free text, now required; `start_date`, labeled "Preferred Start Date", was previously optional, now required — while the free-text `description` field moved the other way, from required to optional, see below); every other care-receiver field — `feeding_type`, `has_medical_condition`, `toilet_assistance`, `requires_vital_monitoring` — is optional on the form and, left unselected (or submitted empty), is defaulted server-side to a real, explicit value: `feeding_type` → `oral_independent`, `has_medical_condition` → `false`, `toilet_assistance` → `[independent]`, `requires_vital_monitoring` → `false`. These defaults are persisted (not left null), so they show up identically to an explicit selection everywhere — caregiver-app's job card and admin-web's edit-prefill both just render whatever is stored, with no special "defaulted" handling needed. **"About Patient"** (age, gender, weight, feeding, has-medical-condition + conditions, toilet assistance — multi-select, admin can pick more than one: `uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`others`/`independent` — and vital monitoring: Yes/No, if Yes multi-select which vitals: blood pressure/blood sugar/oxygen-SpO₂/temperature/pulse/other — this was previously split into a separate "About Patient Condition" section; that section no longer exists, everything lives under "About Patient" now — `mobility` has since been removed from the product entirely, see the Mobility enum entry below), and **"About Nurse/Caregiver Requirement"** (salary, "Hours Care Needed" — one of exactly 3 fixed shifts, see "Duty Type" below, no separately admin-entered start/end time — Frequency of Care (`daily`/`monthly`, required), "Preferred Start Date" (required), and soft caregiver preferences: language preference is **multi-select** (`languages`, a non-empty array — not a single value), gender and religion are single-select; preferred religion offers `hindu`/`muslim`/`christian` only — **`others` is excluded**, it remains valid for a caregiver's own religion at registration, just not offered as a job preference; preferred religion (and language) stay purely informational tags never used as a filter, but **preferred gender is enforced server-side** — `GET /caregiver/jobs` only returns jobs whose `preferred_gender` is unset (no preference) or matches the requesting caregiver's own `caregiver_profiles.gender`, so a caregiver never sees a job posted for the other gender; this filtering happens in `JobsRepository.listActiveForCaregiver`, not in the caregiver-app UI). Job Location (city, area — both required) is its own section above these two; the free-text `description` field (label shortened to "More details you want to share about patient" — previously required, now optional) sits below them. **This "Job Location"/"About Patient"/"About Nurse/Caregiver Requirement" three-section layout, with Vital Monitoring/description present, describes admin-web's create/edit form as originally built and still describes caregiver-app's own job card labels/fields (caregiver-app was not touched by the later change below) — except Communication, which caregiver-app's job card no longer shows either, now that it's been removed from the product entirely. admin-web's own create/edit UI (`_JobFormDialog`) has since been unified with nursenow-app's field set/order instead — see the "universally applicable" `_JobFormDialog` bullet under "NurseNow" below — dropping Communication/Vital Monitoring/description from admin-web's form entirely and renaming its sections to Patient Details/Care Preferences/Nurse Fee Guidance; `requires_vital_monitoring`/`vital_monitoring_types`/`description` still exist as fields (still shown on caregiver-app's job card, and are still defaulted server-side), admin just no longer has a UI to set them — `communication` was later removed from the product entirely (see its own enum entry above), so unlike these it no longer exists as a field anywhere at all.** A `care_receivers` row is created 1:1 with each job (not an independently reusable/searchable entity yet — a future "Patient" app will eventually supply real care-receiver identity data; this only captures the care-needs description). **Every one of these details is visible to caregivers too** — `GET /caregiver/jobs` joins in the full `care_receiver` (not just `GET /admin/jobs/:id`), and caregiver-app's job card renders it under the same two section labels, so a caregiver sees the full patient/condition/requirement picture directly on the jobs list, no separate detail screen needed. Caregivers **apply** or **reject** (`POST /caregiver/jobs/:id/apply`) — there's no "ask for more details" option. Admin reviews applicants, contacts them outside the app, then **accepts** one via `PATCH /admin/jobs/:jobId/applications/:applicationId` — this is the offer confirmation, not a separate in-app caregiver acceptance step. Accepting closes the job (`status = 'closed'`, no more applications) and sets that caregiver's `verification_status` to `assigned`. Admin can later reject that same accepted application to reopen the job and set the caregiver back to `available`. Other still-`applied` applications on a job are left untouched when one gets accepted — not auto-rejected. Admin can view a job's full details and edit any field (via `PATCH /admin/jobs/:id`, same shape/validation as create) — same job id, existing applications untouched regardless of status (including one with an accepted/assigned applicant). If the job was `closed` when edited, saving the edit also **reposts** it: status flips back to `active` and the "New Job" push re-broadcasts to all caregivers; editing an already-`active` job does not resend that push. **Once accepted, the caregiver can see and contact whoever posted the job** — `GET /caregiver/jobs/assigned` includes `job_poster: { full_name, phone }`, the posting admin's contact info, per job. This is deliberately scoped to that one endpoint only — never on the browse list (`GET /caregiver/jobs`) — since admin contact info is only shared once there's an actual accepted engagement, not to every caregiver browsing jobs. Shown in two places in caregiver-app: always on the MyJobs tab (the durable historical record — one contact card per job), and also on the Profile tab but only while `verification_status` is currently `assigned` (Profile fetches `GET /caregiver/jobs/assigned` itself, gated on that status, so it doesn't keep showing a past job's poster(s) once the caregiver is available again). **A caregiver can be accepted onto more than one job at once** — nothing in the eligibility check (`available`/`assigned` are both apply-eligible) or in `decideApplication` prevents a second acceptance while already `assigned`. `GET /caregiver/jobs/assigned` therefore returns an **array**, not a single job/null — every job the caregiver currently holds an `accepted` or `completed` `job_applications` row for, oldest-decision-first by `updated_at`; this is the durable history the MyJobs tab renders (one card per job), so a completed job stays listed rather than disappearing. Each accepted job in MyJobs gets its own **"Mark Complete"** button, calling `POST /caregiver/jobs/:id/complete` (caregiver-only, no body) — this flips just that one `job_applications` row to a fourth status, `completed` (with a `completed_at` timestamp, mirroring `applied_at`/`accepted_at`/`rejected_at`), and only drops `caregiver_profiles.verification_status` back to `available` once **no other `accepted` applications remain**; if the caregiver still holds another active job, `verification_status` stays `assigned`. `JOB_008` covers every case where completion doesn't apply — never applied to that job, still `applied`, already `rejected`, or already `completed`. The job itself is never reopened by completion (stays `closed`). **The caregiver's own application (`GET /caregiver/jobs`'s `my_application`) carries the real per-transition timeline** (`applied_at`/`accepted_at`/`rejected_at`, each null until that transition happens), not just the bare current `status` — a caregiver's own self-decline and an admin un-accepting them both land on `status = 'rejected'` in the DB, and `decided_by_admin` (derived from `decided_by IS NOT NULL`) is what tells them apart; caregiver-app shows "Declined: <date>" for the former and "Declined by employer: <date>" for the latter, alongside "Applied: <date>" and "Accepted: <date>" (if it happened) — never a bare unqualified "You declined". **Admin-web gets the same timeline, plus who decided it**: each row in `GET /admin/jobs/:id`'s `applications` array carries `applied_at`/`accepted_at`/`rejected_at` and `decided_by_name` (the deciding admin's `full_name`, resolved via a `LEFT JOIN users` on `decided_by` — `null` while `status = 'applied'` or on a caregiver self-decline). The Job Applicants dialog renders this under each applicant as "Applied: <date>", "Accepted: <date> by <admin>", and/or "Declined by <admin>: <date>".
- **Closing an accepted job/requirement is labeled "Close", never "Reject", in caregiver-app's MyJobs** — the button (`_completeJob`/`_completeRequirement` in `my_assignment_screen.dart`), confirmation dialog, and status line ("You closed this job — work completed") were previously labeled "Reject"/"rejected" even though the resulting status is `completed` (work done), which read as though the caregiver had declined the engagement rather than finished it. "Reject" stays the correct label everywhere else a caregiver can land on the real `rejected` status — declining a job outright from the browse list, or withdrawing a still-`applied` (not yet accepted) application (`jobs_screen.dart`'s `_rejectJob`/`_withdrawJob`) — since those genuinely produce `status = 'rejected'`, a different outcome from a post-acceptance close. Same server call as before (`POST /caregiver/jobs/:id/complete`); only the UI wording changed. **The caregiver can always apply again afterward** if the job reopens (unchanged existing behavior — see `assigned → available` in the status-transition notes below). nursenow-app's own `_ApplicantTile` already said "Closed by Caregiver" for this same event before this change — the two apps' terminology is now consistent.
- **Both sides now see the full action timeline (who did what, and exactly when) for a job/requirement, not just the latest transition or a bare status word.** caregiver-app's `ApplicationTimeline` widget (`job_detail_card.dart`, shared between the Jobs browse list and MyJobs — previously private to `jobs_screen.dart` and only shown pre-acceptance) renders every entry newest-first: "Applied by you", "Re-applied by you", "Accepted by employer", "Closed by you" (new — added for the `completed` status this session), "Declined by you"/"Declined by employer" (+ reason). Embedding it in `_AssignedJobCard`/`_AssignedRequirementCard` too means MyJobs now shows this same history, not just a bare "You were accepted"/"You closed this job" line. nursenow-app's `_ApplicantTile` (`jobs_posted_screen.dart`) got the equivalent upgrade — previously showed only the single latest transition's timestamp (via `updated_at`, mislabeled "Closed"/"Rejected" with no "Applied"/"Accepted" line at all); now a `_ApplicantTimeline` sub-widget renders the full history newest-first (same convention as caregiver-app's `ApplicationTimeline`) — "Applied", "Accepted" + `decided_by_name` when set, "Closed by Caregiver", "Rejected by <decided_by_name or 'Caregiver'>" + reason, "Re-applied" — naming exactly who decided (the patient/family themselves, or an admin who intervened via admin-web) rather than a vague "you"/"the employer". This surfaced a real gap in the shared Dart model: `JobApplicationModel` (the admin/patient-facing shape, distinct from the caregiver's own `MyApplicationModel` which already had it) was missing a `completedAt` field even though the backend already returns `completed_at` in every `job_applications` row (`ja.*` in `JobApplicationsRepository.findByJobId`, used by both admin's and the individual's own applications endpoints) — purely a client-side parsing gap, no backend change needed. Organisation's own equivalent screen (`requirements_posted_screen.dart`) was **not** touched — it uses a different, older model (`OrganisationRequirementApplicationModel`) with no timeline at all; left as a known, deliberate scope gap (matching the established "NurseNow individual-specific, not extended to Organisation without an explicit ask" precedent elsewhere in this doc) rather than assumed in-scope.
- **admin-web's Jobs list opens read-only by default, not straight into an editable form.** Tapping a job row (anywhere except its action buttons) opens `JobReadOnlyDetailDialog` — every field as plain text, grouped Patient Details / Care Preferences / Nurse Fee Guidance, in the exact same field set and order as `_JobFormDialog` (see the "universally applicable" bullet under "NurseNow" below — this is what admin actually reviews before approving via Edit or rejecting, so it deliberately shows nothing beyond what the create/edit form itself collects: no Communication, Vital Monitoring, or free-text description row, even for an older job that has non-default values stored for them) — with its own **Edit** button that hands off to the existing `_JobFormDialog` edit flow. The row's own explicit **Edit** `TextButton` still jumps straight into the editable form as a shortcut, unchanged; the read-only view is an additional entry point, not a replacement for it.
- **Job display id, salary, and apply-by urgency:** Every job has a display id shown at the top of the job card/row on admin-web, caregiver-app, and nursenow-app — `ADMIN-JOB-<n>` for an admin-posted job or `PAT-JOB-<n>` for a NurseNow individual/patient-posted job (migration 047), each a dedicated sequence starting at 500, backed by the nullable `jobs.admin_job_number`/`jobs.patient_job_number` columns (exactly one is set per row, mutually exclusive by who posted it — set at INSERT time via `JobsRepository.create`'s `posted_by_role` parameter). **The original single shared `jobs.job_number` column (SERIAL from 1, used for both posters alike before `admin_job_number`/`patient_job_number` existed) has been dropped entirely** — it had already stopped being displayed anywhere once the two newer sequences took over, and was kept for a while afterward only as an internal fallback/audit-log-resolution aid; once every table's data was wiped for a fresh start, that fallback had no remaining legacy rows to be compatible with, so the column (and its owned sequence, `jobs_job_number_seq`, dropped automatically along with it) was removed along with every reference to it — `JobsRepository`/`AuditLogsRepository`/`AdminReportsRepository`/`admin.service.ts` on the backend, `JobModel`/`AuditLogEntry` and admin-web's audit-logs/reports screens on the frontend. `jobDisplayId(JobModel)` (`packages/vitacare_shared/lib/models/job_model.dart`) now throws if neither `adminJobNumber` nor `patientJobNumber` is set, rather than falling back to the removed field — a job matching neither is a data-integrity bug, not a case to silently paper over, since exactly one is always set at INSERT time. The shared helper picks the right prefix so all three Flutter apps render identical text; an analogous `organisationJobDisplayId(OrganisationRequirementModel)` formats an organisation-posted requirement as `ORG-JOB-<n>` (reusing `organisation_requirements.requirement_number`, whose sequence was rebased to start at 500 in the same migration — no new column needed there since that table has only one possible poster type). Admin sets a single required `salary_amount` when posting or editing a job; its unit follows the job's `frequency_of_care` (₹/day for `daily`, ₹/month for `monthly`), and this dynamic unit is shown everywhere the figure appears — admin-web's form label and job list row, and caregiver-app's job card, which shows it highlighted prominently at the top. Every job also carries `posted_at` (starts equal to `created_at`, but is bumped to "now" only when a `closed` job is edited-and-reposted — a plain edit of an already-`active` job leaves it untouched) driving a caregiver-facing **3-day apply-by urgency window**: `posted_at + 3 days`, shown as "Posted: <date>" plus a days-left message ("X days left to apply" / "Last day..." / "Application window closed"). This is purely informational — it does not block applying, and the job itself is not auto-closed when the window passes; admin must still close (or let it be) manually.
- **`jobs.area`/`start_date`/`frequency_of_care`/`salary_amount`/`care_duration` and `caregiver_profiles.religion` are all DB-level `NOT NULL`** — each used to be nullable purely to accommodate rows that predated the field becoming application-required (documented at the time as e.g. "nullable... because admin-posted jobs and every row that predates this column leave it null"); once every table's data was wiped for a fresh start, those legacy-compatibility reasons no longer applied, so each column was tightened with `ALTER TABLE ... SET NOT NULL` and the corresponding backend TypeScript types (`JobRecord`/`CreateJobInput`/`UpdateJobInput` in `jobs.repository.ts`, `CaregiverProfileFullRecord.religion` in `caregiver-profiles.repository.ts`) were narrowed to drop the `| null`. This is safe precisely because every current code path already always supplies these fields (`CreateJobDto`/`UpdateJobInput`/`CreateIndividualRequirementDto` require `area`/`start_date`/`frequency_of_care`/`salary_amount`/`care_duration` unconditionally now — see the Frequency of Care/Salary derivation and Duration Care is Needed sections above — and `RegisterDto.religion` has always been required at registration). The Dart-side `JobModel` fields for these same columns are deliberately left nullable (`String?`) as a defensive superset rather than tightened to match — safe either way, just a looser type — to avoid a much larger, riskier sweep through every UI consumer's null-handling across three apps.
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
- **Force-upgrade:** admin-web has an "App Versions" screen (any admin, not just super_admin) where an admin sets a `min_version` (and optional `store_url`/`update_message`) per platform (`android`/`ios`) in the `app_min_versions` table — **one row per platform**, full stop (two rows total). The single JustHeal binary (`apps/justheal-app`, covering both the caregiver and patient/hospital flows — see "Merged into one binary with NurseJobs" below) checks `GET /app-versions/check?platform=&version=` (public, no auth) once on every cold launch, via the host's own `AppVersionRepository.checkForUpdate()` (`lib/patient_hospital/core/version/`) — and if its own build (`PackageInfo.version`) is below `min_version`, shows a full-screen, non-dismissible `UpdateRequiredScreen` with the admin's `update_message` (or a generic default) and an "Update Now" button linking to `store_url`; nothing else in the app loads until the user updates. Platform is determined via `defaultTargetPlatform` (not `dart:io Platform`, which doesn't compile for the web dev target this app is also tested against) — anything other than iOS is treated as `android`. The version check is deliberately **fail-open**: any error (network down, backend unreachable, malformed response) is caught and treated as "no update needed," since a broken check must never be able to lock every user out. admin-web itself has no equivalent gate — it's a web app that just needs a browser reload to pick up a new deploy (see Firebase Hosting cache note), not a store-distributed binary.
  **History**: this briefly carried an `app` dimension (`nursejobs`/`nursenow`, migration 068) so NurseJobs and NurseNow could be force-upgraded independently, back when they shipped as two separate binaries each with their own version number. Once they merged into the single JustHeal binary, that independence became fictional — there's only one real installed app version to check, and only the host's own splash screen actually ran the check post-merge (the ported caregiver flow's own copy of the same check, in `lib/caregiver/core/version/`, became unreachable dead code — nothing navigates to its route anymore, see below). **Migration 074 collapsed both `app_min_versions` and `app_maintenance` back to platform-only / a single global row** and deleted the now-pointless caregiver-side copies of these two repositories; admin-web's "App Versions" and "Maintenance Mode" settings tabs each show one control (per platform, and one overall, respectively) instead of two independent NurseJobs/NurseNow sections.
- **Maintenance Mode:** admin-web's "Maintenance Mode" settings tab lets an admin take the whole JustHeal app down with a custom message, via a **singleton** `app_maintenance` row (`id` fixed to 1, same convention as `rate_card`/`scope_of_work`/`duty_requirements`). Checked by the host's own `AppMaintenanceRepository.checkForMaintenance()` (`GET /app-maintenance/check`, public, no params) alongside the version check on every cold launch — same fail-open contract. Also collapsed from a per-app design by migration 074 (see "Force-upgrade" above) — there is no longer a way to take down just the caregiver or just the patient/hospital side; enabling it blocks everyone, since they're one binary now.
- **Login Settings (OTP mode) is the one exception that stayed per-app** (`otp_auth_settings`, keyed by `nursejobs`/`nursenow`) — unlike Force-upgrade/Maintenance, this is a genuine product choice (PIN vs OTP) that can still legitimately differ between the caregiver and patient/hospital screens even inside one binary, so migration 074 left it untouched. The subtlety: it can no longer be fetched once at a shared cold-launch splash the way it used to be, since the merge means only ONE splash screen (the host's own, `lib/patient_hospital/.../splash_screen.dart`) is a real entry point — the ported caregiver splash (`lib/caregiver/features/auth/screens/splash_screen.dart`, registered at the bare `/caregiver` route) is unreachable; nothing navigates to it (`/caregiver/register` and `/caregiver/login` are reached directly from the host's own screens). So each app's `otpModeProvider` is set independently, by whichever of its own screens actually needs it: the host's splash fetches `nursenow`'s setting for its own login/registration screens, while caregiver's own `registration_screen.dart` and `login_screen.dart` each fetch `nursejobs`'s setting themselves in their own `initState` (rather than depending on the now-unreachable caregiver splash to have done it first). Getting this wrong would be a real outage, not just a display bug: the backend's `AuthService.resolveCredential` enforces OTP mode server-side regardless of what the client sends (`AUTH_010` if a PIN is sent while OTP is required) — if a caregiver-facing screen didn't know OTP mode was on, it would keep showing the PIN field while the backend keeps rejecting it, with no way for a user to self-recover.

## NurseNow (Patient/Family + Hospital/Rehab) — published as JustHeal

**Naming (2026-10):** this app/codebase is still referred to as "NurseNow" throughout this
doc and in Dart code (package name `nursenow_app`, class names like `NurseNowApp`/
`NurseNowBottomNav`) — that internal name was never changed. What *did* change is the
public identity: the app is published to the app stores as **JustHeal** (Android
`applicationId`/iOS bundle id `in.vitacasahealth.justheal`, `MaterialApp.title` and every
on-screen brand string), and — per the next paragraph — it is no longer a standalone
binary. The company/legal entity remains **VitaCasaHealth Services**, deliberately distinct
from the consumer-facing app name.

**Merged into one binary with NurseJobs (2026-10):** `apps/justheal-app` is the **host
app** for a single published binary that also contains NurseJobs' entire caregiver flow,
ported into `apps/justheal-app/lib/caregiver/` (own `core/`, own route table, every route
prefixed `/caregiver/...` to avoid colliding with this app's own `/login`, `/register`,
`/profile`, etc. — see the "caregiver-app" mentions elsewhere in this doc for why the two
flows stay internally separate rather than being redesigned into one UX). A caregiver
reaches that flow via a **"Caregivers Registration"** button in the top-right of this app's
`LoginScreen`, which pushes `/caregiver/register`. The app's own non-caregiver code
(individual/organisation) lives in `apps/justheal-app/lib/patient_hospital/`, sitting
alongside `lib/caregiver/` — the two trees stay internally separate on disk as well as in
routing. **The old standalone `apps/caregiver-app`** (kept in place, unpublished, as the
source of truth for the ported code until the merged flow was fully verified) **has since
been deleted** — the merge was verified end-to-end (unit/widget tests, live Chrome
smoke-testing of registration/login/the unified-login fallback) and the directory was a
pure duplicate at that point, so it was removed rather than left to drift out of sync.

A separate companion app, **NurseNow**, lets patients/families and
hospitals/rehabs/clinics post care requirements and get matched against the same caregiver
pool NurseJobs already serves, sharing the same backend (`apps/api`) and Postgres DB.
**Both account types are now built:
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
  caregiver-app). `POST /auth/register/individual` (`phone`, `code`) creates the `users` row plus
  a 1:1 `individual_profiles` row; `POST /auth/login/code` is shared with caregiver login
  (role-generalized check). No account-level admin approval gate — an individual can post a
  requirement immediately after registering. **`full_name` is no longer collected on the
  registration form at all** (`RegisterIndividualDto.full_name` is optional; the JustHeal
  registration screen's Individual branch has no name field — only Organisation still has one,
  labeled "Contact person name") — `AuthService.registerIndividual` defaults `users.full_name` to
  the phone number itself when omitted, so `users.full_name` stays `NOT NULL` with no schema
  change, and every existing display spot (admin-web's Patients/Family list/search, the job-poster
  contact card shown to an accepted caregiver, audit logs, etc.) still has something identifiable
  to show rather than a blank. The individual's own Profile screen already has a self-edit "Full
  Name" field (`updateName`, pre-existing, unaffected by this change) — an individual can still set
  a real name anytime after registering, it's just no longer required up front.
- **Registration IS posting, for Individual accounts.** The old standalone "Post a Requirement"
  screen (`PostRequirementScreen`) has been deleted entirely — every field it used to collect
  (About Patient / Care Preferences / the Salary guidance bar / the derived-tier line) is now
  merged directly into `RegistrationScreen`'s Individual branch (Organisation's own registration
  fields — contact name, org name/type/city/area — are untouched; Organisation still posts
  separately via its own `PostOrganisationRequirementScreen`, unaffected). The Terms & Conditions
  checkbox sits at the very bottom of the form, after every requirement field, right above the
  submit button — which reads **"Post Requirement"** for Individual (still "Register" for
  Organisation). Submitting calls `POST /auth/register/individual` followed immediately by
  `POST /individual/requirements` in the same action — registering the account and creating its
  one requirement together. **Since a phone number can only ever register once** (`AUTH_001`/
  `AUTH_016`), this means an individual can post **at most one requirement in the lifetime of that
  phone number** — there is no "post a new one later" entry point anywhere else in the app:
  `JobsPostedScreen` no longer has a "Post a Requirement" CTA (not even once the one requirement
  closes/is rejected — the old "no live requirement" gating that allowed reposting is gone), and
  its per-card "More options" menu dropped "Post Similar Requirement" (now just Edit/Cancel,
  2 actions instead of 3). `EditRequirementScreen` is untouched — editing the one requirement
  already posted is not the same as posting a new one, and remains available at any point in its
  lifecycle exactly as before. If `POST /individual/requirements` fails right after a successful
  registration (e.g. a transient network error), the user is left on the registration screen with
  the error shown and can simply tap "Post Requirement" again — `RegistrationScreen._submit()`
  checks `sessionProvider` first and skips straight to the create-requirement call if the account
  is already authenticated, rather than attempting to re-register (which would just 409).
- **Posting flow:** `POST /individual/requirements` takes the same shape as admin's job-posting
  form (About Patient + city/area/duty_type/start_date/languages/preferred_gender/
  preferred_religion), created with `status: 'pending_review'` (admin still reviews for
  legitimacy before it goes live). It also collects `care_duration` ("Duration Care is Needed" —
  `few_days`/`few_weeks`/`few_months`/`long_term`, see "Care Duration" below), shown right below
  "Preferred Start Date" in nursenow-app's Post/Edit Requirement forms and in
  `JobsPostedScreen`'s read-only detail — required, like every other hard-required field on this
  form. **`frequency_of_care` and `salary_amount` are no longer admin-set on approval — they're
  client-derived and included in the POST body from the moment of creation**, and freely
  overwritable on every subsequent edit; there is no `pending_review`-gated waiting period for
  pricing at all any more (the old `JOB_013` error code, which used to block setting them before
  admin's first approval, was removed as unused once the gate was removed). `frequency_of_care`
  is derived from `care_duration` via `frequencyForCareDuration()` (few days/weeks → `daily`, few
  months/long term → `monthly`, `packages/vitacare_shared/lib/models/rate_suggestion.dart`) and
  rendered as a read-only `InputDecorator`, never a manual dropdown, anywhere a job/requirement is
  created or edited. `salary_amount` is pre-filled from the public Rate Card's suggested figure
  for the tier derived by `deriveCareTier()` (see "Scope of Work" above) and that same frequency,
  via `suggestedRate()` in the same file — but stays a normal free-text field the patient (or
  admin) can always type over. Both nursenow-app's `PostRequirementScreen`/`EditRequirementScreen`
  reactively recompute the suggestion as Toilet Assistance/Feeding Type/Medical Condition/Duration
  Care is Needed change (`_refreshSuggestedSalary()`, guarded so it never overwrites something the
  patient already typed — only refills while the field is still empty or still holds the system's
  own last suggestion), fetching the Rate Card once via `_loadRateCards()` in `initState`.
  `EditRequirementScreen` additionally has to handle the case where Salary is pre-filled from the
  requirement's *existing* `salary_amount` before the Rate Card fetch resolves: `_loadRateCards()`
  unconditionally overwrites with the first resolved suggestion regardless of what's already in
  the field (mirroring what happens when the requirement is first created), while
  `_refreshSuggestedSalary()` is the guarded version used for every later reactive recomputation —
  getting this backwards (a single guarded refresh from `initState`) incorrectly treats the
  pre-existing salary as patient-protected and never applies the fresh suggestion. **An Individual
  account may have at most one "live" requirement at a time**, where "live" includes a
  not-yet-approved `pending_review` one — enforced server-side (`JOB_009`) via
  `JobsRepository.findLiveByPostedBy`. Admin's own approval is now just a legitimacy review — the
  same `PATCH /admin/jobs/:id` edit dialog transitions `pending_review → active` and stamps
  `posted_at` (reusing the repost/push-broadcast path that already reactivates a `closed` job on
  edit) without touching pricing, since the individual already set it. Admin can instead **reject**
  a `pending_review` job via `PATCH /admin/jobs/:id/reject` (`{ reason }`, admin/super_admin only)
  — sets `status: 'closed'` and `jobs.rejection_reason`, visible to the individual on their own
  requirement view; only valid from `pending_review` (`JOB_011` otherwise).
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
  **nursenow-app has a 2-tab bottom nav for Organisation and a 3-tab one for Individual**
  (`NurseNowBottomNav`, mirroring NurseJobs' `CaregiverBottomNav`): **Profile** (`/profile` —
  identity, phone/PIN self-edit, Logout, shared route for both account types) and, Individual only,
  **Messages** (`/messages` — `MessagesScreen`, see below) in between, then **Requirement Posted**
  (`/home` — `JobsPostedScreen`'s AppBar title and bottom-nav label, both renamed from "Jobs
  Posted"/"Jobs Posted" — the class/file name itself is unchanged — reflecting that there is now
  only ever one requirement, never a plural list of separately-posted jobs; the full requirement
  history described above, each card showing the full About Patient / About Nurse-Caregiver
  Requirement detail inline, an always-visible applicants list once a requirement leaves
  `pending_review` [so an accepted caregiver's name/phone stay visible after the job closes].
  **No "Post a Requirement" CTA** — posting only ever happens once, as part of registration itself
  (see "Registration IS posting" above), so this screen's history list holds exactly one
  requirement per account, full stop. **No "Show Closed/Cancelled Requirements" toggle either** —
  that only ever made sense when an account could accumulate multiple past postings; now every
  requirement in history (0 or 1 in practice) is shown directly. A cancelled requirement is not a
  dead end: `POST /individual/requirements/:jobId/reactivate` (`IndividualService
  .reactivateRequirement`, mirrors `OrganisationRequirementsService.reactivateRequirement` —
  `JobsRepository.activate()` flips `status` back to `active`, clears `cancelled_at`, bumps
  `posted_at`, same as a repost) brings it back to active with no admin re-review needed (the
  content was already vetted the first time it went live) — `JOB_017` if the requirement was never
  cancelled (an admin-rejected one, `rejection_reason` set, can never be self-reactivated, same
  asymmetry as cancel's own `JOB_015`), `JOB_010` if the account is job-posting-blocked. The
  per-card "More options" menu shows **"Make Active Again"** instead of "Cancel the Job" once a
  requirement is cancelled — the two are mutually exclusive, never both offered at once.
- **`JobsPostedScreen`'s requirement card is the only place a requirement is ever edited — every
  field is always shown, pre-filled, and directly editable right there.** The old "Show Full
  Details" collapse/expand toggle and the separate, full-screen `EditRequirementScreen` (reached
  via a now-deleted "Edit the Job" menu action) are both gone — deleted entirely, not just hidden.
  `_RequirementCardState` carries the same field set/validation/Rate-Card-salary-suggestion logic
  `EditRequirementScreen` used to (ported verbatim: `SectionBox`-grouped "Patient Details"/"Care
  Preferences", the amber Salary block with its derived-tier line, the same mandatory-field
  highlight-and-scroll), initialized from the requirement in `initState`/`_populateFromRequirement`
  and submitted via the same `IndividualRepository.editRequirement` call. **Editing is never
  locked, even once a candidate has applied/been accepted** — `IndividualService.editRequirement`'s
  old `JOB_014` check (block editing while there's an active application) was removed on explicit
  request; Organisation's own `editRequirement` (`OrganisationRequirementsService`) still enforces
  its own separate `JOB_014` lock, this relaxation is Individual-specific. Instead: **tapping Save
  while an active (applied/accepted) application exists shows a confirmation dialog first**
  ("Modify this requirement? ... We recommend discussing any changes with the candidates directly
  before saving.", `_confirmModifyWithActiveApplicants` — only shown once the edit is otherwise
  valid, and only for an active application, not a rejected/completed one) — saving only proceeds
  if confirmed. **Save/discard controls are a tick/cross `IconButton` pair shown inline, right next
  to whichever field was actually touched** (as each field's own `suffixIcon`, or alongside its
  label for the two fields with no `InputDecoration` — Medical Condition's chips, Preferred Start
  Date's button) — not one consolidated pair at the bottom of the card, which on a form this long
  landed below the fold and wasn't visible without scrolling. Each field has its own dirty getter
  (`_isAgeDirty`/`_isGenderDirty`/etc., each comparing just that field against
  `widget.requirement`/its `care_receiver`, set-based for the multi-value ones) and its own revert
  method (`_revertAge`/etc., resetting only that field) — `_fieldControls(fieldName, dirty,
  onRevert)` renders the pair (`Key('$fieldName-save')`/`Key('$fieldName-discard')`) only when that
  one field differs from what's saved. **Every field's tick runs the exact same action** — there's
  no partial-field save endpoint, so whichever tick is tapped re-runs the full mandatory-field
  validation, then the active-application confirmation if applicable, then saves the form's entire
  current state (every pending edit across every field at once) via one `editRequirement` call;
  each field's own cross only reverts that one field, leaving any other still-pending edits
  untouched. No form-wide "discard everything" action exists any more. The per-card "More options" menu
  dropped its "Edit the Job" action entirely, now offering only Cancel/Make Active Again (see
  above). **Unlike every other field in this card, Salary is
  deliberately read-only — not a text field, same as the registration form's own salary display**
  (see "Registration IS posting" above): bold standout `Text`, never user-typed, auto-filled
  purely from the Rate Card suggestion for the derived care tier/frequency and re-derived live as
  Toilet Assistance/Feeding Type/Medical Condition/Duration Care is Needed change on this same
  card. A fixed guidance line sits above it — "This is just a guidance, you must discuss it
  directly with caregivers. Fees are paid directly to the Nurse/Caregivers." — and the derived-tier
  line (tap the tier name for the Scope of Work popup) sits below it. Still what gets submitted as
  `salary_amount` on Save, and still mandatory (`_isSalaryValid`) for the highlight-and-scroll
  validation, just with no `FocusNode` of its own (there's no field to focus on a `Text` widget).
- **Messages** (`/messages` — `MessagesScreen`, Individual-only) is a purely **client-computed**
  tab — no new backend endpoint, no persistence, no read/unread state. It re-fetches the account's
  own requirements via the same `GET /individual/requirements` call `JobsPostedScreen` makes, then
  runs each one through `messagesForRequirement(JobModel)`
  (`features/individual/data/requirement_messages.dart`), which returns a `List<String>` of every
  tip that currently applies — always reflecting whatever the requirement's current status/care
  needs are right now, recomputed fresh on every load, nothing dismissible or marked-seen. Returns
  nothing at all once the requirement is no longer live (`pending_review`/`active` — the same
  `isLive` concept `JobsPostedScreen`/`JOB_009` use elsewhere). While live, up to 4 messages apply,
  always in this fixed order (not a real timeline — none of these are one-off events with their
  own timestamp):
  1. "You can edit this job and change salary. Typically it takes 3 to 5 days for caregivers to
     reach out. If urgent, do not hesitate to click on the red button at the top of the app for
     help." (the "red button" is the existing `WhatsAppHelpButton`, styled `AppColors.error`) —
     always shown while live.
  2. "Based on the patient's condition we see you need `<tier>`..." — only once the requirement
     has a `care_receiver` (always true once actually posted; a defensive `null`-check purely for
     robustness). The tier names `deriveCareTier(careReceiver)` derives (`CareTier.displayNames`),
     the same derivation `ScopeOfWorkButton`/the Post/Edit form's own clickable tier line use —
     points the patient at the Rate Card and Scope of Work features for that tier.
  3. "You can post one requirement at a time…" — a static explainer of the one-live-requirement
     rule (`JOB_009`) and that cancelling is always available, shown while live regardless of any
     other field.
  4. "If you are not getting applicants, consider widening your scope…" (monthly/long-term,
     religion, and caregiver-gender preference) — shown unconditionally while live, **not**
     gated on the requirement's actual current preferences or how long it's been posted; "everyday
     there should be a message if a job is live" was interpreted as "keeps appearing every day the
     job stays live" given the deliberately-computed-not-persisted architecture (see below), not a
     literal once-per-calendar-day dedup, which would need state to track.

  **Before the account has ever posted a requirement at all** (not merely "no *live* one right
  now"), `welcomeMessages(List<JobModel>)` (same file) supplies a 2-message first-time
  welcome/orientation instead — explains what each of the 3 tabs is for, then prompts posting a
  first requirement via Jobs Posted. Same non-persisted, non-dismissible architecture as
  `messagesForRequirement`: it needs no "already seen" flag because posting a first requirement is
  itself a real, permanent state change (`requirements.isNotEmpty`) — the welcome message simply
  stops applying forever at that point, nothing to track. `MessagesScreen.build()` just prepends
  `welcomeMessages(_requirements)` to the per-requirement list; each function independently
  returns empty in the other's domain, so there's no special-casing needed to combine them.

  This was a deliberate architecture choice on request: **computed live from data already fetched,
  no backend changes** — the simpler of two options considered, the other being a real
  backend-tracked message table with read/unread state and permanent history; that was explicitly
  turned down in favor of this one. `NurseNowBottomNav`'s tab-index mapping is **different per
  account type** — Individual is `[Profile, Messages, Jobs Posted]` (0/1/2), Organisation stays
  `[Profile, Requirements]` (0/1) — every screen's own `bottomNavigationBar` passes its own fixed
  `currentIndex` matching its position in whichever list applies to its account type.
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
  path is also how a candidate the caregiver self-withdrew from can be accepted after all. **The
  same "Accept Anyway" action also works on a `completed` application** — a caregiver who closed
  this job themselves (`POST /caregiver/jobs/:id/complete`, see "Closing an accepted job" above)
  can be re-engaged by the same patient/family: `completeJob` already reopens the job to `active`
  server-side, so `decideApplication`'s accept path just needed a 3rd eligibility case
  (`isAcceptFromCompleted`, alongside the existing `isAcceptFromApplied`/`isAcceptFromRejected`) to
  allow it — no other side effect differs from a fresh accept (closes the job again, sets the
  caregiver back to `assigned`). `_ApplicantTile` shows "Accept Anyway" (not plain "Accept") for
  this case too (`_isRejected || _isCompleted`), and `canAccept` no longer excludes a `completed`
  application the way it originally did (that exclusion was a deliberate initial design choice,
  later reversed on explicit request). The `JOB_016` guard lives in the shared `decideApplication`
  method, so it applies equally if admin's own accept-an-applicant flow is ever used the same way.
  **Rejecting an applicant requires a
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
  **On nursenow-app's Post/Edit Requirement screens, focus is requested *before* the scroll, with a
  300ms wait in between when the target has a `FocusNode` (a text field, not a dropdown)** — this
  order matters specifically on an actual mobile device: `requestFocus()` opens the on-screen
  keyboard, which shrinks the viewport; computing the scroll position beforehand (the original
  order) meant the keyboard's later resize could cover the field right after the scroll had placed
  it in view, so the fix worked on desktop/web (no on-screen keyboard) but not on a phone. Fixed by
  reordering to focus-then-wait-then-`Scrollable.ensureVisible` — re-fetching `target.key.
  currentContext` fresh after the delay (with a `ctx.mounted` check) rather than reusing a context
  captured before the async gap.
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
  order too. `EditRequirementScreen` additionally keeps its existing conditional **"Nurse Fee
  Guidance"** section (renamed from "Frequency & Salary"; only shown once the requirement has been
  approved at least once) as its own third `SectionBox`, opening with a fixed helper line — "You
  can always negotiate with nurse staff." — above the Frequency of Care/Salary fields. **Frequency
  of Care is no longer a manual dropdown here** — it's derived from the patient's own Duration Care
  is Needed selection (`frequencyForCareDuration()`, `packages/vitacare_shared/lib/models/
  rate_suggestion.dart`): `few_days`/`few_weeks` → `daily`, `few_months`/`long_term` → `monthly`.
  Rendered as a plain read-only `InputDecorator` (no dropdown arrow, nothing to pick) rather than a
  `DropdownButtonFormField`. **Salary is pre-filled with a suggested rate looked up from the Rate
  Card** — `suggestedRate()` (same file) takes the tier derived by the existing `deriveCareTier()`
  (reusing the toilet-assistance/feeding-type/medical-condition fields already live-edited on this
  same screen, not a stale snapshot from when the requirement was first posted) and the frequency
  above, and returns the matching Rate Card cell text for that tier's column (Companion/Bedside/
  Critical, index-matched to `CareTier.all`) from whichever frequency's single "Care" row. Fetched
  once via `rateCardRepositoryProvider` in `initState` (`_loadSuggestedRate`) and fails open — a
  network error, or the Rate Card simply not resolving to a suggestion, just leaves whatever was
  already in the field (the requirement's existing `salary_amount`) untouched. The field stays a
  normal editable `TextField` either way — admin/the patient can always type over the suggestion,
  matching the helper text above it. Because a suggested rate can be a whole sentence (a range with
  a note, e.g. "26000 pm/867 per day\nTo\n30000 pm/1000 per day depending on experience"), **
  `jobs.salary_amount` is now `TEXT`, not `INTEGER`** (migration 060; `jobs_salary_amount_check`
  numeric constraint dropped) — this is a schema change shared with admin's own job-posting/editing
  form (`CreateJobDto.salary_amount`, `apps/admin-web`'s `_JobFormDialog`), which is otherwise
  unaffected: admin still types a plain number in a numeric-keyboard `TextField` with the same
  1–1,000,000 client-side range check, just converted to a string (`.toString()`) at submission
  time rather than sent as a number. **`organisation_requirements.salary_amount` is a separate
  column on a separate table and was NOT changed** — Rate Card guidance has never applied to
  Organisation postings, so there's no derivation to feed it; it stays a plain admin-entered
  `INTEGER`. The free-text "More details you want to share about
  patient" field is removed from both forms entirely (NurseNow-specific — admin-web's own job
  posting form still has its own equivalent `description` field, untouched). **`JobsPostedScreen`'s
  own read-only "Show Full Details" expander mirrors this same grouping** — a `_DetailRow`
  label-above-value line per field (label small/secondary, value default body text), under the
  same "Patient Details"/"Care Preferences" headings in the same field order, replacing the old
  "About Patient"/"Patient Care Requirement" headings and their undifferentiated `Wrap` of bare
  `_Tag` chips (which made e.g. a lone "Male" chip ambiguous — patient's own gender, or a
  caregiver preference?). `_Tag` was removed as dead code once nothing referenced it anymore. It
  also has a third **"Nurse Fee Guidance"** section (Frequency of Care, Salary), matching the
  Post/Edit form's own final section — added once Frequency/Salary stopped being admin-approval-
  gated (see the individual-requirement Frequency/Salary bullet above): the requirement card's own
  collapsed salary line (`₹<amount>/day` or `/month`, shown above the primary action button) used
  to only render `if (requirement.status == JobStatus.active ...)`, since `salary_amount` used to
  be null until admin approved; now that it's always set from creation, that condition just checks
  `salary_amount != null`, so a `pending_review` requirement's own figure is visible to the patient
  immediately, not just once it goes live.
- **nursenow-app's `PostRequirementScreen`/`EditRequirementScreen` no longer have a "Nurse Fee
  Guidance" `SectionBox` at all — Salary now lives in a sticky bar pinned below the AppBar
  (`_buildSalaryBar`, a `Column`'s non-scrolling first child, sibling to the `Expanded`
  `ListView` holding "Patient Details"/"Care Preferences" — not inside the scrollable content),
  and Frequency of Care is no longer displayed anywhere on either screen.** This is
  NurseNow-Individual-specific — admin-web's `_JobFormDialog` and `JobsPostedScreen`'s own
  read-only "Show Full Details" expander (see below) are both untouched, still showing Frequency
  of Care and Salary inline in their own "Nurse Fee Guidance" section. Frequency of Care is still
  derived internally exactly as before (`_derivedFrequencyOfCare`/`frequencyForCareDuration()`) —
  it just drives the Salary bar's `₹/day` vs `₹/month` unit and what's submitted as
  `frequency_of_care`, rather than being shown as its own field; before any Duration Care is Needed
  selection, the unit defaults to `₹/month` (`_derivedFrequencyOfCare == FrequencyOfCare.daily ?
  'day' : 'month'`, unchanged ternary from before — null read as "not daily"). The "You can always
  negotiate with nurse staff." helper line moved into the same bar, directly under the Salary
  field. **`PostRequirementScreen` also no longer shows the "An admin reviews every new requirement
  before it goes live and caregivers can see it." info banner** that used to sit above "Patient
  Details" — removed outright, not relocated. **The Salary input itself only appears once Duration
  Care is Needed, Toilet Assistance, and Feeding/Medicine Assistance are all filled in** — exactly
  the 3 fields the derived tier/frequency (and therefore the Rate Card suggestion) depend on;
  until then the bar shows a placeholder hint ("Salary will appear here once...") in the same spot
  instead of an input with nothing meaningful to suggest yet. This is a pure UI gate — `_salaryKey`
  is still positioned after `_toiletAssistanceKey`/`_feedingTypeKey` in `_mandatoryFieldsInOrder`,
  so Submit's highlight-and-scroll never targets a Salary field that isn't in the tree yet (those 3
  fields are already guaranteed valid by the time the mandatory-field loop would reach Salary).
  When editing an existing requirement (`EditRequirementScreen`), these 3 fields are normally
  already pre-filled from it in `initState`, so the Salary input appears immediately in practice.
  **The bar itself is styled as a bold yellow ribbon** — `Colors.amber` solid fill, rounded bottom
  corners, a drop shadow lifting it off the page — rather than a plain white bordered box, so the
  single most important figure on the form reads as a banner rather than just another field; the
  Salary `TextField` itself keeps a white `filled` background so it still reads as editable against
  the colored ribbon. No icon or "SALARY" heading sits above the input (the field's own label
  already says "Salary") — text placed directly on the ribbon (the placeholder hint before the
  field is ready, and the "You can always negotiate with nurse staff." caption below it) uses
  `AppColors.textPrimary` (dark), not white, for readable contrast against yellow. **The field's
  label reads "Salary (₹/day) (Negotiable)" / "Salary (₹/month) (Negotiable)"** — "(Mandatory)" was
  renamed to "(Negotiable)" purely as a wording choice matching the negotiate caption below it; the
  field is still validation-mandatory for submission (`_isSalaryValid` still gates Submit and the
  mandatory-field highlight-and-scroll), only the displayed label text changed.
- **admin-web's job form (`_JobFormDialog` in
  `apps/admin-web/lib/features/jobs/screens/admin_jobs_screen.dart`, used for both admin's own
  from-scratch job posting AND creating/editing any job via `POST`/`PATCH /admin/jobs`) has one
  unified field set and order for every case — no more branching between "admin's own posting" and
  "editing an individual's requirement".** It matches nursenow-app's own Post/Edit Requirement
  screens exactly: **Patient Details** (age/gender/weight/city/area, then Medical Condition) →
  **Care Preferences** (Hours Care Needed, Preferred Start Date, Duration Care is Needed, Toilet
  Assistance, Feeding/Medicine Assistance, Preferred Caregiver Gender, Language Preference,
  Preferred Caregiver Religion) → **Nurse Fee Guidance** (Frequency of Care, Salary). Vital
  Monitoring (the toggle + monitoring-types multi-select) and the free-text "more details"
  description field are **not offered in admin-web's form at all any more** — removed entirely,
  not just hidden; the backend still accepts and defaults them server-side (`description` staying
  optional in `CreateJobDto`), so a job created or re-edited via admin-web simply freezes those
  fields at their defaults rather than admin ever setting them. Communication used to follow the
  same pattern but has since been removed from the product entirely (see its own enum entry) — it
  no longer exists to freeze at a default. **Duration Care is Needed is now collected on admin's own from-scratch postings
  too** (`CreateJobDto.care_duration` is unconditionally required — this was a real functional gap
  before this field existed in admin-web's UI, since the backend already required it and
  admin-web's create/update calls had no way to supply it). **Medical Condition switched from a
  toggle-then-reveal `SwitchListTile` to nursenow-app's always-visible mandatory multi-select with
  a "None" sentinel** (`_noneMedicalCondition`/`_applyMedicalConditionSelection`, mirroring
  `_noPreferenceLanguage`'s own mutual-exclusivity pattern) — defaults to "None", picking any real
  condition clears it, and it can never be truly empty so it needs no separate red-highlight
  validation. **Frequency of Care is always derived from Duration Care is Needed
  (`_derivedFrequencyOfCare`, same `frequencyForCareDuration()` helper) and rendered as a
  read-only `InputDecorator`, never a manual dropdown — for every job admin creates or edits, not
  only a NurseNow individual's.** Salary is always a free-text field pre-filled from the Rate
  Card's suggestion for the derived tier/frequency (`_loadRateCards()`/`_refreshSuggestedSalary()`)
  and reactively recomputed as Toilet Assistance/Feeding Type/Medical Condition/Duration Care is
  Needed change — never a numeric-validated manual entry; the old 1–1,000,000 numeric range check
  is gone along with the numeric keyboard. **Unlike nursenow-app's own `EditRequirementScreen`
  (which unconditionally overwrites Salary with the first resolved suggestion on load, even over a
  pre-filled existing value — correct there since the patient is editing their own posting),
  admin-web's `_loadRateCards()` uses the same *guarded* fill `_refreshSuggestedSalary()` always
  has: only into an empty field, never overwriting a pre-filled existing job's real
  `salary_amount`.** This matters specifically because admin is often approving/editing a job that
  already carries a real salary — set by the NurseNow patient themselves, or a previous admin edit
  — and that value must never be silently replaced the instant the Rate Card resolves; a brand-new
  job (Salary starts empty) still gets the initial suggestion exactly as before.
  `AdminJobsRepository.create()`/`.update()` both gained a required `careDuration` parameter to
  match.
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
  has document depth — `IndividualDetailScreen` does have its own Notes section now, see below,
  just as a plain boxed section rather than a tab) showing identity + status, an **Edit** toggle,
  and a scoped audit-history preview (`GET /admin/audit-logs?target_user_id=...`, same pattern as
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
- **Admin-initiated PIN/login-code reset — caregiver, individual, and organisation accounts
  alike.** Previously the only way to change a login PIN was self-service (`PATCH .../profile/code`
  on each of `CaregiverService`/`IndividualService`/`OrganisationService`, all hashing via
  `bcrypt`/`UsersRepository.updateCodeHash` with no old-code check). Admin now has the identical
  capability over any account: `POST /admin/caregivers/:id/reset-code`,
  `POST /admin/individuals/:id/reset-code`, `POST /admin/organisations/:id/reset-code` (same
  `:id` convention as each role's other admin endpoints — `caregiver_profiles.id` for caregivers,
  `users.id` directly for individuals/organisations), all reusing caregiver's own `UpdateCodeDto`
  (`{ code }`, `Validation.CODE_REGEX` — exactly 4 digits) and audit-logged via the new
  `AuditAction.ADMIN_CODE_RESET` (entity type `'caregiver_profiles'`/`'individual_profiles'`/
  `'organisation_profiles'`) — kept distinct from `CODE_CHANGED` precisely so audit logs show
  *who* reset it. Admin types the new PIN directly (no old-PIN check, no system-generated
  random code) — `apps/admin-web/lib/shared/widgets/reset_pin_dialog.dart`'s
  `showResetPinDialog()` is the one shared dialog all three detail screens
  (`CaregiverDetailScreen`/`IndividualDetailScreen`/`OrganisationDetailScreen`) call via their own
  "Reset PIN" button, each then calling their own repository's `resetCode(id, code)`.
- **Admin-only personal/internal notes on jobs, individual (patient/family), and organisation
  accounts** — distinct from the caregiver-only `admin_notes` table (which stays hard-FK'd to
  `caregiver_profiles`, see "Admin Notes" elsewhere in this doc). Three new tables: migration 075
  added `job_admin_notes` (`job_id` FK → `jobs`, `UNIQUE(job_id)`) and `individual_admin_notes`
  (`user_id` FK → `users`, `UNIQUE(user_id)`); migration 076 added `organisation_admin_notes`
  (`user_id` FK → `users`, `UNIQUE(user_id)`) once the organisation case was explicitly asked for
  too (initially scoped out as "not asked for" — see git history — then added on request, same
  shape as the other two). All three are the same one-row-per-entity upsert shape as `admin_notes`,
  just a single free-text `notes` column each (no `availability_remarks`/rate fields, which are
  caregiver-specific concepts). `JobsService.upsertNotes`/`AdminIndividualsService.upsertNotes`/
  `AdminOrganisationsService.upsertNotes` all reuse the shared `UpsertNotesDto` (`{ notes }`) and
  audit-log via the existing `AuditAction.ADMIN_NOTE_ADDED` (entity type
  `'job_admin_notes'`/`'individual_admin_notes'`/`'organisation_admin_notes'`) — no new audit
  action needed since this is the same *kind* of event as the caregiver notes case, just a
  different entity. `notes` is merged into `GET /admin/jobs/:id`'s, `GET /admin/individuals/:id`'s,
  and `GET /admin/organisations/:id`'s existing response shape (`jobs.service.ts`'s
  `getJobDetailForAdmin`, `admin-individuals.service.ts`'s `getIndividualDetail`,
  `admin-organisations.service.ts`'s `getOrganisationDetail`) rather than a separate fetch — never
  present on any caregiver/individual/organisation-facing endpoint (`JobModel.notes` in
  `vitacare_shared` is admin-response-only, same convention as
  `postedByRole`/`postedByName`/`postedByPhone` on the same model). admin-web:
  `IndividualDetailScreen`/`OrganisationDetailScreen` each get their own boxed "Notes" section
  (editable, independent Save/Cancel, same edit-toggle pattern as the "Profile" section above it)
  between Profile and Audit History; `JobReadOnlyDetailDialog` gets a small `_JobNotesSection` (its
  own tiny `ConsumerStatefulWidget`, since the rest of that dialog is a plain `StatelessWidget`)
  appended after Nurse Fee Guidance/Scope of Work. All three follow the same "No notes yet." empty
  state plus Edit/Save/Cancel controls.
- **Admin-initiated phone-number change — caregiver, individual, and organisation accounts
  alike.** Folded into each role's existing single admin-edit endpoint/dialog rather than a new
  one: `phone` is now an optional field on `AdminEditCaregiverDto`/`AdminEditIndividualDto`/
  `AdminEditOrganisationDto` (`Validation.PHONE_REGEX`), diffed and written the same way every
  other tracked field already is, so it shows up in the same `AuditAction.ADMIN_EDIT_PROFILE`
  entry alongside whatever else changed in the same edit. It's a plain in-place
  `UsersRepository.updatePhone(userId, phone, client)` on the existing `users` row — **the
  profile, every job/requirement posted, and every application are completely untouched**, since
  all of them key on `user_id`, never on `phone`; this was the explicit point of the request, and
  it's just a natural consequence of not creating a new account. Still dedup-checked exactly like
  each role's own self-service `updatePhone` — caregiver checks `findByPhoneAndRoles(phone,
  [CAREGIVER])`, individual/organisation check `findByPhoneAndRoles(phone, [INDIVIDUAL,
  ORGANISATION])` (not the global `findByPhoneAnyRole` — same same-bucket-only scope self-service
  already uses, not expanded here) — `AUTH_001` if another account in that bucket already holds
  it. **Deliberately does NOT trigger a caregiver's re-review/`pending_call` reset** the way the
  caregiver's own self-service phone change does (see "Phone is identity-sensitive" elsewhere in
  this doc) — admin edits are already treated as trusted everywhere else in `AdminService
  .editProfile` (verification_status is left alone for every other field too), so phone follows
  that same precedent rather than the self-service one. admin-web: each of
  `CaregiverDetailScreen`/`IndividualDetailScreen`/`OrganisationDetailScreen`'s existing Profile
  edit form gained a Phone `TextField` right next to Full Name, with a helper line making the
  "same account" guarantee explicit in the UI — no new endpoint, button, or dialog, since this
  reuses the Edit toggle + Save Changes flow each screen already had.

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
  `type_of_nurse` (plus conditional `type_of_nurse_other` when `type_of_nurse === 'others'`),
  `accommodation_provided`, `food_provided`, optional `special_skills`, optional
  `number_of_vacancies` (1–49, defaults to 1 server-side), optional `preferred_gender`
  (`male`/`female` only — no preference if omitted), and `duration_type` (see "Requirement
  Duration" below) — no care_receiver, no city/area/duty_type/start_date (inherited from the
  org's own registered location), and **no `frequency_of_care`/`salary_amount`/scheduling fields
  at all** — Rate Card guidance has never applied to organisation postings (see "Rate Card"
  above), and there is no admin-set pricing/scheduling step for an organisation requirement to
  wait on. Created with `status: 'pending_review'`. **Unlike Individual, there is no
  one-live-requirement limit** — an org can have many simultaneous postings, since a
  hospital/rehab genuinely needs to fill several openings at once; this was a deliberate scope
  difference, not an oversight.
- **Admin's own edit mirrors exactly what the org itself can set, nothing more.**
  `PATCH /admin/organisation-requirements/:id` (`AdminEditOrganisationRequirementDto`) accepts the
  same field set as the org's own self-edit (`UpdateMyOrganisationRequirementDto` —
  `type_of_nurse`/`type_of_nurse_other`/`accommodation_provided`/`food_provided`/
  `special_skills`/`number_of_vacancies`/`preferred_gender`/`duration_type`), but every field is
  optional here, merged field-by-field over the existing row
  (`OrganisationRequirementsService.adminEditRequirement`) — **a bare/empty body is a valid
  request and works as a pure approve**, transitioning `pending_review` (or a `closed`
  requirement) to `active` and stamping `posted_at`, with no pricing or scheduling fields for
  admin to fill in along the way. This reverses an earlier design where admin owned none of these
  fields at all (a pure approve/reject click); it was changed on explicit request so admin can
  now also correct any org-owned field while approving, rather than rejecting and asking the org
  to re-submit. Admin can instead **reject** via
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
  pending_review only, and **Edit**, doubling as "Approve" from `pending_review`, editing the same
  Type of Nurse/Number of Vacancies/Duration Type/Preferred Gender/Accommodation/Food/Special
  Skills fields the org itself can set, nothing more — no pricing or scheduling fields, see
  "Organisation" above) are extracted into `apps/admin-web/lib/features/organisation_requirements/widgets/
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

Two admin-editable salary-guidance grids, one per frequency of care (`rate_card` table, migration
058 — "one row per key" like `app_min_versions`/`otp_auth_settings`, `frequency_of_care VARCHAR(10)
PRIMARY KEY CHECK (frequency_of_care IN ('daily', 'monthly'))`, reusing the existing
`FrequencyOfCare` enum values as the key), shown behind a persistent green "Rate Card" pill button
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
`update_required_screen.dart` (a non-dismissible blocking screen). This replaced an earlier
single-grid design (migration 052, a strict `id=1` singleton) whose cells manually mixed both
figures per box (e.g. "26000 pm/867 per day") — admin now maintains the two frequencies as fully
independent grids, each with its own title/labels/cells, and both caregiver-app and nursenow-app
show both to the caregiver/individual at once (stacked in the same dialog, not a toggle/tab),
since a caregiver may be weighing either a daily or a monthly engagement.

- **Shape is fixed per grid (3 columns x 1 row), only the text is admin-editable.**
  `column_labels` is always exactly 3 entries, `row_labels` always exactly 1 (the single "Care"
  row); `cells[row][col]` a matching 1x3 grid — every label, cell, and the title are free-text
  strings, not structured amount+unit fields, since the source data mixes plain rates, a range
  with a note ("35000-42000 pm (depending on years of experience)"), and a plain refusal
  ("Caregivers are not suggested") — forcing a rigid numeric shape would lose that. There's no
  add/remove-row/column UI, and no way to add a third frequency — not requested. Originally a 3x3
  grid (3 caregiver tiers: Care / Nursing students-backlogs / Nurses) — migration 059 dropped the
  "Nursing students/Nursing with backlogs" and "Nurses (Nursing completed/Registered/Unregistered)"
  rows from both the daily and monthly grids, keeping only "Care", since the tiering wasn't needed.
  `column_labels` (Companion/Bedside/Critical Care) is untouched.
- **Backend** (`apps/api/src/rate-card/`): `GET /rate-card` is public (no auth), always returns
  both rows as an array — both apps fetch fresh on every icon tap, no caching/global state.
  `GET /admin/rate-card` (both rows, each with `updated_by_name`) and
  `PATCH /admin/rate-card/:frequency` (frequency in the URL path, not the body — the body is just
  `{title, column_labels, row_labels, cells}`) are `ADMIN`/`SUPER_ADMIN`-only; an unrecognized
  `:frequency` 404s with `GEN_002` (mirroring `AppConfigService.adminUpdate`'s handling of an
  invalid platform param), checked before `RATE_001`'s shape validation so a bad frequency never
  masks itself as a shape error. Each update is audit-logged via `AuditAction.RATE_CARD_UPDATED`
  (entityType `'rate_card'`, no `entityId` — `frequency_of_care` is a `VARCHAR`, not a `UUID`, so
  it can't be put in `audit_logs.entity_id`; same pattern as `otp_auth_settings`, which also has a
  non-UUID PK). `RATE_001` covers a malformed `cells` shape (not exactly 1 row of exactly 3
  strings) — checked in `RateCardService`, not via class-validator decorators, since there's
  no clean built-in decorator for a nested `string[][]`; `UpdateRateCardDto.row_labels` also has a
  matching `@ArrayMinSize(1)/@ArrayMaxSize(1)`. Updating one frequency never touches the
  other row.
- **admin-web**: `/rate-card` screen (`features/rate_card/`) renders two independently-editable,
  independently-saveable sections stacked on one page — one per frequency, each its own bordered
  box with its own title field, 3x1 `Table` of label/cell `TextField`s, "last updated by" line, and
  **own Save button** (a separate `PATCH .../:frequency` call per section, not one combined save) —
  not the list-of-dialogs pattern App Versions uses, since a grid doesn't fit well in a cramped
  dialog. `RateCardRepository.get()` returns `List<RateCardWithUpdater>` (always 2, one per
  frequency); `.update(frequency, model)` takes the frequency explicitly since it's no longer part
  of the request body. Reuses the shared `RateCardModel` (`packages/vitacare_shared`, now carrying
  a `frequencyOfCare` field alongside title/labels/cells — excluded from `toJson()` since it's a
  URL path param, not a body field).
- **Mobile apps**: `RateCardButton` (`apps/*/lib/app/rate_card_button.dart`) is duplicated per app
  (not shared via `vitacare_ui`, which is restricted to colors/spacing/micro-widgets only, not
  full dialogs with network calls) — same duplication precedent as `WhatsAppHelpButton`.
  `RateCardRepository.get()` returns `List<RateCardModel>` (always both frequencies); tapping opens
  an `AlertDialog` rendering both grids read-only, stacked with each one's own title as a heading
  and a divider between them; a failed fetch shows a friendly inline error rather than crashing or
  blocking anything, since this is purely informational. Both `RateCardButton` and
  `WhatsAppHelpButton` (both apps) are wrapped in a `Padding(right: 6)` — without it, whichever of
  the two rendered last in an AppBar's `actions` list sat flush against the screen's right edge,
  since both buttons' own internal padding was already trimmed to near zero to fit 3-action AppBars
  (RateCard + WhatsApp + Logout) without overflowing.
- **The mobile Rate Card dialog is responsive to the device's actual width, not a fixed 400px box**
  — `_RateCardDialogState.build()` sizes its content to `(MediaQuery width - 32).clamp(280, 560)`
  and tightens `AlertDialog.insetPadding` to 16px horizontal (from the Material default 40px), and
  `_RateCardTable` uses `FlexColumnWidth` (row-label column at 0.7, each data column at 1) instead
  of the old fixed pixel widths (140px label / 150px per cell) — together this means both the daily
  and monthly cards' full 4-column tables fit within the dialog's own width without ever needing
  the horizontal scroll the old fixed-width table required; long cell text (e.g. a Rate Card range
  with a note) wraps onto multiple lines instead. The outer vertical `SingleChildScrollView` stays
  as a defensive fallback (in case of an unusually long admin-typed value on a very short screen)
  but is not expected to engage on a typical phone, since each card is just a title + a 2-row
  table. This is identical duplicated code in both `apps/justheal-app/lib/caregiver/` and
  `apps/justheal-app/lib/patient_hospital/`'s own `rate_card_button.dart`, same duplication
  precedent as the rest of this button.

## Scope of Work

A single, admin-editable set of 3 cumulative bullet lists — **Companion Care**, **Bedside Care**
("Everything in Companion Care, plus…"), **Critical Care** ("Everything in Bedside Care,
plus…") — stored in the `scope_of_work` table (migration 055, a singleton row like `rate_card`).
Shown to caregivers (NurseJobs) via a per-job **"Scope of Work"** button on `JobDetailCard`
(`apps/justheal-app/lib/caregiver/features/jobs/widgets/job_detail_card.dart`, next to "Show details" —
shared by both the Jobs list and MyJobs, and only rendered when `job.careReceiver != null`), never
shown on Organisation-posted requirements (`_RequirementCard`), which have no `care_receiver` to
derive a tier from — same exclusion `RateCardButton` already applies to Organisation accounts, for
the same "these guidelines are for individual hiring, not institutional bulk hiring" reason.

- **The tier is derived, never manually picked.** `deriveCareTier(CareReceiverModel)`
  (`packages/vitacare_shared/lib/models/care_tier.dart`) reads only `toilet_assistance` and
  `feeding_type` and picks exactly one of `CareTier.companionCare`/`bedsideCare`/`criticalCare`,
  checked highest-tier-first: **Critical Care** if `toilet_assistance` includes `uses_catheter` or
  `others`, or `feeding_type` is `tube_feeding`/`others` ("Others (Cannula etc.)") — any single one
  of these four is enough on its own, regardless of what's selected on the other axis; else
  **Bedside Care** if `toilet_assistance` includes `diapers_bedside_support`; else **Companion
  Care** (the baseline case — `independent` toileting + `oral_feeding`). **`has_medical_condition`/
  `medical_conditions` and `requires_vital_monitoring` do NOT factor into tier derivation at
  all** — both fields are still collected and shown everywhere they were before, they simply no
  longer move the tier or the suggested rate (previously, several specific medical conditions and
  vital monitoring each independently triggered Critical, and any medical condition triggered
  Bedside; that was removed in favor of this Toilet-Assistance/Feeding-Type-only rule, and
  `others` toileting moved from a Bedside trigger to a Critical trigger in the same change). This
  mapping is a product judgment call documented in code comments right at the function, not
  something the backend enforces — reviewable in one place if the intended tiering changes.
  Neither `communication` nor `mobility` (both removed from the product entirely, see their own
  enum entries above) factor into the rule either. The popup shows only the derived tier's bullets, stacked cumulatively with
  every tier below it via `ScopeOfWorkModel.bulletsFor(tier)` — never the full 3-tier table.
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
  - **caregiver-app** (`apps/justheal-app/lib/caregiver/app/scope_of_work_button.dart`): inline on
    `JobDetailCard`, next to "Show details" — shared by the Jobs list and MyJobs.
  - **nursenow-app** (`apps/justheal-app/lib/patient_hospital/app/scope_of_work_button.dart`, own
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
- **nursenow-app's Post/Edit Requirement screens surface the derived tier directly under the
  Salary ribbon, as a clickable line** — "Based on the requirements you entered, this appears to
  be a `<tier>`." with the tier name itself tappable, opening the exact same Scope of Work dialog
  the standalone `ScopeOfWorkButton` uses. To make this reusable, `apps/justheal-app/lib/
  patient_hospital/app/scope_of_work_button.dart`'s dialog widget was renamed from private `_ScopeOfWorkDialog` to
  public `ScopeOfWorkDialog` (and its `State` class to `ScopeOfWorkDialogState`) — both
  `ScopeOfWorkButton` and `PostRequirementScreen`/`EditRequirementScreen`'s own
  `_buildDerivedTierLine()` construct it directly (`showDialog(builder: (_) => ScopeOfWorkDialog(
  tier: ..., repository: ref.read(scopeOfWorkRepositoryProvider)))`), rather than duplicating the
  fetch/loading/error logic. This replaced the old "You can always negotiate with nurse staff."
  static caption that used to sit in the same spot on the Salary ribbon — removed outright, not
  kept alongside the new line.

## Duty Requirements

A single admin-editable set of 3 independent bullet lists — **24Hrs - Live In**, **12Hrs Day
Shift (8am to 8pm)**, **12Hrs Night Shift (8pm to 8am)** — stored in the `duty_requirements` table
(migration/psql-applied directly like `scope_of_work`/`rate_card`; a singleton row, `id` fixed to
1 by a DB CHECK). Describes what the patient/family must **arrange for the nurse** under each
shift (bedding/meals/supplies, no cooking or household chores, etc.) — a wholly separate concept
from Scope of Work (which describes caregiving **tasks** by care tier, not what the family must
arrange by shift) and from Rate Card (salary guidance). **Unlike Scope of Work's tiers, these 3
lists are NOT cumulative** — each shift stands alone; `DutyRequirementsModel.bulletsFor(dutyType)`
just returns that one shift's own list, no stacking.

- **Backend** (`apps/api/src/duty-requirements/`): mirrors `scope-of-work`'s exact shape — `GET
  /duty-requirements` is public (no auth); `GET /admin/duty-requirements` (adds
  `updated_by_name`) and `PATCH /admin/duty-requirements` are `ADMIN`/`SUPER_ADMIN`-only, audit-
  logged via `AuditAction.DUTY_REQUIREMENTS_UPDATED` (entityType `'duty_requirements'`, no
  `entityId`, same non-UUID-PK reasoning as `rate_card`/`scope_of_work`). `DUTY_001` covers an
  empty list or a list containing a blank/whitespace-only bullet — checked in
  `DutyRequirementsService`, not via class-validator, since `@IsString({each: true})` alone
  doesn't reject blank strings (identical reasoning to `SCOPE_001`). `audit_logs.action`'s DB-level
  CHECK constraint had to be widened (dropped and re-added with `duty_requirements_updated`
  appended) to accept the new action value — the TypeScript/Dart enum additions alone aren't
  enough, since the column itself is constrained.
- **nursenow-app**: `DutyRequirementsInfoButton` (`features/individual/widgets/
  duty_requirements_button.dart`) — a small ⓘ icon button next to "Hours Care Needed" on
  `PostRequirementScreen`/`EditRequirementScreen`, disabled until a shift is actually selected
  (the content is entirely shift-specific, no sensible default to show beforehand). Tapping it
  opens `DutyRequirementsDialog`, which fetches `GET /duty-requirements` fresh on every tap (own
  `DutyRequirementsRepository`/`dutyRequirementsRepositoryProvider`, not cached) and renders
  `dutyRequirements.bulletsFor(selectedDutyType)`. Not shown anywhere else (not on admin-web's job
  form or Organisation's posting screen) — this is patient/family-facing operational guidance for
  a NurseNow Individual posting specifically.
- **admin-web**: `/duty-requirements` screen (`features/duty_requirements/`) — same free-length-
  bullet-list editing pattern as `/scope-of-work` (every bullet its own `TextField` with a delete
  button, plus an "Add bullet" button per shift section), just 3 independent sections instead of
  3 cumulative tiers. `DutyRequirementsRepository.get()` returns a `DutyRequirementsWithUpdater`
  wrapper (hits authenticated `GET /admin/duty-requirements`); `.update()` sends a bare
  `DutyRequirementsModel` to `PATCH /admin/duty-requirements`. Reachable via a "Duty Requirements"
  sidebar nav item (any admin, unconditional — same placement convention as Rate Card/Scope of
  Work) and registered in `root_screen.dart`'s `_restorableRoutes` safe-list (the page-refresh-
  stays-on-page fix — every new static admin-web route needs this).

## Admin Push Notifications

Admin can select any mix of caregiver/individual/organisation accounts and send them a custom
FCM push notification, immediately or scheduled for a future date/time — "admin to many,"
reusing each account type's existing admin-web list screen (with its own existing search/filter)
as the selection UI rather than building a new one.

- **A prerequisite this surfaced: individual/organisation accounts never registered an FCM
  token at all before this feature.** Only caregivers had `PUT /caregiver/fcm-token` +
  caregiver-app's own `FcmService` (`lib/caregiver/core/fcm/fcm_service.dart`, called from
  `SessionNotifier.loadSession()` and the registration screen). Added the same capability for
  the other two roles: `PUT /individual/profile/fcm-token` / `PUT /organisation/profile/fcm-token`
  (both reuse the existing `UpdateFcmTokenDto`, both just call `UsersRepository.updateFcmToken`
  with no audit log, same as caregiver's own `updateFcmToken`), and a patient_hospital-side
  `FcmService` (`lib/patient_hospital/core/fcm/fcm_service.dart`) that mirrors caregiver's
  exactly except `register({required bool isOrganisation})` takes the role explicitly (patient_
  hospital's `SessionNotifier` already decodes it from the JWT via `_isOrganisationToken` to pick
  which `getMe()` to call — the same boolean is now also passed to `_fcmService.register()` right
  before `loadSession()` returns, mirroring caregiver's `unawaited(_fcmService.register())`).
  `RegistrationScreen._submit()` needed no separate wiring since both its Individual and
  Organisation branches already call `sessionProvider.notifier.loadSession()` immediately after
  registering, which now does this transitively.
- **Backend** (`apps/api/src/admin-push-notifications/`): two new tables, migration 077 —
  `admin_push_notifications` (`created_by`, `title`, `body`, `scheduled_at`, `sent_at`, `status`
  — `pending`/`sent`/`failed`/`cancelled`, `PushNotificationStatus` enum — `recipient_count`) and
  `admin_push_notification_recipients` (`notification_id` FK, plain `user_id` — role-agnostic, no
  FK to any one profile table, since one notification can target a mix of all three account
  types at once). `POST /admin/push-notifications` (`CreatePushNotificationDto` — `title`, `body`,
  optional `scheduled_at` ISO 8601, `recipient_user_ids` array capped at
  `Validation.PUSH_NOTIFICATION_MAX_RECIPIENTS` [5000], same bulk-safety-cap convention as
  `BULK_DELETE_MAX_ITEMS`) creates the row and, if `scheduled_at` is omitted or already in the
  past, sends it in the same request — the response's own `status` reflects whether it actually
  went out (`sent`) or not (`failed`), never an optimistic claim regardless of outcome (`
  AdminPushNotificationsService.create` uses `send()`'s own boolean return to decide which).
  Otherwise it's left `pending` for `AdminPushNotificationsService.processDueNotifications` — a
  `@Cron('* * * * *')` minute-poll (same `@nestjs/schedule` infra `FcmService`'s own daily
  reminder already uses) that finds every `pending` row whose `scheduled_at` has arrived and sends
  it; low enough volume (admin-composed, not a per-user trigger) that a simple poll is plenty, no
  overlap guard needed. Sending resolves the notification's recipient user ids, looks up their
  `fcm_token`s via the new role-agnostic `UsersRepository.listFcmTokensByUserIds`, and calls the
  new generic `FcmService.sendToTokens(tokens, title, body)` (unlike every other `FcmService`
  method, which is always caregiver-only and swallows+logs its own errors, this one throws so the
  caller can mark the notification `failed` rather than silently losing that signal). `GET
  /admin/push-notifications` lists history (paginated, newest first, joined with the creating
  admin's name). `PATCH /admin/push-notifications/:id/cancel` only succeeds on a still-`pending`
  row (`PUSH_001` otherwise) — `AdminPushNotificationsRepository.cancel` does the `status='pending'`
  guard as part of the `UPDATE ... WHERE` clause itself, atomically. Both create and cancel
  audit-log (`AuditAction.PUSH_NOTIFICATION_CREATED`/`PUSH_NOTIFICATION_CANCELLED`, entity type
  `'admin_push_notifications'`) — nothing is audit-logged for the cron's own send/fail transition,
  since that's a system action with no admin attributable to it beyond the original create.
- **admin-web — recipient selection cart**: a plain Riverpod `StateNotifierProvider`
  (`shared/state/recipient_selection_cart.dart`, `recipientSelectionCartProvider`) holding
  `Map<String, SelectedRecipient>` (`userId`, `role`, `displayName`) — deliberately just a provider,
  not tied to any one screen's widget tree, so it persists as admin navigates between the
  Caregivers/Patients-Family/Rehab-Hospitals list screens. Each of those three screens' existing
  `DataTable`/mobile `VitaListCard` rows gained a `Checkbox` (plus a header "select all on this
  page" checkbox for the `DataTable` case, additive via `addAll`/`removeAll` — never replaces
  a selection made on a different page or a different screen) toggling membership — no new
  search/filter UI, reusing each screen's own existing one entirely as asked. `AppShell` gained an
  optional `bottomBar` slot (threaded through to `Scaffold.bottomNavigationBar` on both the
  permanent-sidebar and compact/Drawer layouts) so `RecipientCartBar`
  (`shared/widgets/recipient_cart_bar.dart`) can float pinned below any screen's content without
  each screen having to restructure its own layout — collapses to nothing when the cart is empty.
  When non-empty, it shows a role breakdown ("3 caregivers, 2 patients, 1 organisation selected")
  plus Clear and "Notify Selected" (opens `ComposeNotificationDialog`).
- **admin-web — compose/schedule** (`features/push_notifications/widgets/compose_notification_dialog.dart`):
  title/body fields (capped at `Validation.pushNotificationTitleMaxLength`/`BodyMaxLength`), a
  `SegmentedButton<bool>` for Send Now vs Schedule for later (not `RadioListTile` — deprecated in
  the Flutter version this app is on), and for the latter a date+time picker pair combined into
  one `DateTime`; Send/Schedule stays disabled until title+body are non-empty and (if scheduling)
  a future date/time is picked. On success, clears the cart (starting a new compose should start
  from an empty selection, not silently resend to the same group) and shows a snackbar reflecting
  the actual returned `status` — "sent to N recipient(s)," "could not be delivered — see Push
  Notifications history," or "scheduled for \<date\>," never a blanket "sent."
- **admin-web — history** (`features/push_notifications/screens/push_notifications_screen.dart`,
  `/push-notifications`, new "Push Notifications" sidebar nav item + `root_screen.dart`
  `_restorableRoutes` entry, same conventions as every other static admin-web route): lists every
  past/pending notification (title, message, recipient count, scheduled date/time, status chip,
  who composed it) with pagination; a pending row gets a Cancel action, nothing else is ever
  editable after composing. This screen is read/cancel-only — composing a new notification only
  ever happens via `RecipientCartBar` from one of the three list screens, never from here.

## Support Tickets ("Forgot PIN")

There's no OTP/email PIN reset (see "No OTP" above — phone login has no OTP, and this doesn't
add one). Instead, a "Forgot PIN?" link on any login screen (caregiver, individual/organisation's
shared login screen) creates a support ticket; admin reviews it in a new admin-web "Tickets"
screen, verifies the requester's identity out of band (a phone call, same as every other identity
check in this product), then resets their PIN using the existing admin Reset PIN action on that
account's own detail screen (see "Admin-initiated phone-number change"/PIN-reset bullets
elsewhere in this doc).

- **Backend** (`apps/api/src/tickets/`): one new table, migration 078 — `support_tickets`
  (`user_id` FK → `users`, deliberately role-agnostic since a ticket can come from a caregiver,
  individual, or organisation account; `type` — a `TicketType` enum, currently only
  `forgot_pin`, kept as its own enum rather than a hardcoded string so a future ticket type never
  needs a migration to the CHECK constraint's shape; `status` — `TicketStatus.open`/`resolved`;
  `phone`; `notes`; `created_at`/`resolved_at`/`resolved_by`). `POST /auth/forgot-pin`
  (`TicketsController`, no `JwtAuthGuard` — reachable before the user can authenticate at all;
  `ForgotPinDto { phone }`) resolves the account via the existing `UsersRepository
  .findByPhoneAnyRole` (phone is globally unique across every registration-facing role — see
  "Phone number is now globally unique" above — so this never needs an `app`/bucket parameter the
  way login does), 404s with the existing `AUTH_002` ("no account found with this phone number")
  if nothing matches — same error login already surfaces for this exact case, so this never
  confirms or denies an account's existence any more precisely than login already does. If the
  resolved account already has an open `forgot_pin` ticket, that one is reused (returns a
  slightly different message) rather than accumulating duplicates from repeated taps.
  `GET /admin/tickets` (`AdminTicketsController`, paginated, optional `status` filter) and
  `PATCH /admin/tickets/:id/resolve` (`ResolveTicketDto { notes? }`, only succeeds on a still-open
  ticket — `TICKET_001` otherwise, same "guard baked into the `UPDATE ... WHERE`" convention as
  `AdminPushNotificationsRepository.cancel`) are admin-only. Both ticket creation and resolution
  are audit-logged (`AuditAction.SUPPORT_TICKET_CREATED`/`SUPPORT_TICKET_RESOLVED`, entity type
  `'support_tickets'`) — creation logs `userId` as the *resolved account's* own user id (same
  "self-service event, logged against the account it happened to" convention as `registration`/
  `login`), resolution logs `userId` as the admin and `targetUserId` as the ticket's requester.
  `TicketsRepository.list`'s query resolves the requester's display id the same way
  `AuditLogsRepository`'s target resolution does (see "Audit Logs target/entity display ids"
  above) — `LEFT JOIN` all three of `caregiver_profiles`/`individual_profiles`/
  `organisation_profiles` on `user_id`, since a ticket's user has exactly one role and therefore
  at most one of `caregiver_number`/`patient_number`/`org_number` is ever non-null.
- **admin-web** (`features/tickets/`): new "Tickets" sidebar nav item + `/tickets` route (+
  `root_screen.dart` `_restorableRoutes` entry, same convention as every other static route) —
  lists tickets (requester name/role/display id/phone, type, status, opened date, who resolved
  it), defaulting to the Open filter, with a Resolve action (optional notes, via a dialog) on each
  open row. Tapping a row's requester opens that account's own detail screen
  (`CaregiverDetailScreen`/`IndividualDetailScreen`/`OrganisationDetailScreen` depending on role —
  same per-role routing as `openAuditTargetDetail` in `audit_entry_cells.dart`), so admin can jump
  straight from the ticket to resetting that account's PIN.
- **Mobile**: `ApiRoutes.forgotPin`, and a `forgotPin(phone)` method on each app's own
  `AuthRepository` (caregiver's and patient_hospital's — both just POST and return the backend's
  own message string, shown as-is). A small `showForgotPinDialog()` helper is duplicated per app
  (`lib/caregiver/app/forgot_pin_dialog.dart` / `lib/patient_hospital/app/forgot_pin_dialog.dart`
  — same duplication precedent as `RateCardButton`/`WhatsAppHelpButton`) — pre-fills the phone
  field from whatever's already typed into the login screen's own phone field, and on submit
  shows the returned message via a `SnackBar`. A "Forgot PIN?" `TextButton` sits right below the
  PIN field on both login screens (PIN-mode only — OTP mode has no PIN to forget).
- **Login screen reorder (patient_hospital only, explicit request)**: this screen's "New here?
  Register as:" section (+ its 3 account-type rows) now renders *above* the "Log in" section
  (phone/PIN or OTP fields, Forgot PIN link, submit button) — previously the reverse. Registration
  is this app's primary conversion path for a new visitor, so it's shown first; a returning user
  scrolls past it to Log in below. Caregiver's own dedicated login screen (`/caregiver/login`) was
  not reordered — it only ever had a single "New here? Register" link already positioned below its
  login form, so no reorder was needed there.

## Account Deletion

A self-service "Delete My Account" option on the Profile screen of all three account types
(caregiver, individual, organisation) — built for Play Store's account-deletion requirement
(an app that allows account creation must also let users delete their account and data, either
in-app or via a documented web process). Deletion requires re-entering the login PIN first (the
only re-auth step anywhere in this product's self-service flows), since it's irreversible.

- **Anonymize-in-place, never a hard delete.** `UsersRepository.anonymizeAndDeactivate(userId,
  client?)` overwrites `phone` (tombstoned to `del_<first 16 hex chars of the user's own id>` —
  always unique with no DB round-trip, and short enough for the `VARCHAR(20)` column),
  `full_name` ('Deleted User'), `email`, `code_hash`, and `fcm_token` (all `NULL`), and sets
  `is_active = false` plus a new `deleted_at` timestamp (migration 079) — it never removes the
  `users` row. A hard delete was ruled out: `job_applications`, `audit_logs`, `support_tickets`,
  and the admin-notes tables all carry FK references to `users.id` that belong to *other*
  people's own records (e.g. a patient's accepted-applicant history), so deleting the row would
  either orphan those or cascade-destroy data that isn't the deleting account's to remove.
  `is_active = false` immediately locks the account out of every further authenticated request
  via the existing `JwtAuthGuard` (same mechanism as an admin-initiated full block/deactivation —
  non-expiring caregiver/individual/organisation JWTs are re-checked against the DB on every
  request, within a 30s cache window), so there's no separate token-revocation step needed.
- **Role-specific PII is each service's own responsibility** — `UsersRepository` only ever
  touches `users`. `CaregiverService.deleteAccount` additionally calls
  `CaregiverProfilesRepository.anonymizeDocuments` (nulls `selfie_photo_url`/
  `qualification_document_url`/`aadhaar_document_url`, resets `other_document_urls` to `'[]'`)
  inside the same `withTransaction` as the users-row update, then — **after** the transaction
  commits, since the DB side already satisfies the deletion and a storage failure must never
  block it — reads every version ever uploaded for that profile via
  `CaregiverDocumentsRepository.listByProfileId` (the full history, not just the current
  selfie/Aadhaar/qualification/other URLs) and removes each one from Supabase Storage via
  `UploadService.deleteFile`, best-effort (`.catch(() => {})` per file — a storage cleanup
  failure is swallowed, never surfaced to the caller).
  `OrganisationService.deleteAccount` additionally calls
  `OrganisationProfilesRepository.anonymizeContactPerson` (the contact person is an individual,
  so their name is anonymized same as `users.full_name`) — `organisation_name`/
  `organisation_type`/`city`/`area` describe the business entity itself, not a person, and are
  left intact as a business record. `IndividualService.deleteAccount` has nothing extra to
  anonymize — `individual_profiles` carries no PII beyond what's already on `users`.
- **Backend**: `DELETE /caregiver/account` / `/individual/account` / `/organisation/account`,
  each role's own controller, all taking the same `DeleteAccountDto { code }` (in
  `caregiver/dto/`, reused by individual/organisation same as `UpdatePhoneDto`/`UpdateCodeDto`).
  The PIN is checked in the service layer (`bcrypt.compare` against the stored `code_hash`),
  throwing the existing `AUTH_008` ("Invalid code") on a mismatch — the same code login uses, not
  a new one, since it's the same kind of failure. Audit-logged via the new
  `AuditAction.ACCOUNT_DELETED` (entity type `caregiver_profiles`/`individual_profiles`/
  `organisation_profiles`, matching whichever account was deleted) — this is the one case where
  the audit log entry survives the very account it's about, since audit rows are an internal
  VitaCasaHealth record of what happened, not data collected from the user that deletion is
  expected to remove (see the Privacy Policy's retention wording).
- **Mobile**: each repository (`ProfileRepository`/`IndividualRepository`/
  `OrganisationRepository`) gained a `deleteAccount(code)` method (`ApiRoutes.caregiverAccount`/
  `.individualAccount`/`.organisationAccount`). `showDeleteAccountDialog()` is duplicated per app
  (`lib/caregiver/app/delete_account_dialog.dart` / `lib/patient_hospital/app/
  delete_account_dialog.dart`, the latter taking `isOrganisation` to pick the right repository —
  same duplication precedent as `RateCardButton`/`WhatsAppHelpButton`/`ForgotPinDialog`) — a
  dialog collecting the PIN with a bold warning, calling the delete itself and showing a wrong-
  PIN error inline (same retry-without-closing pattern as `ForgotPinDialog`), returning `true`
  only once the account is actually gone. The caller (`ProfileViewScreen`/`ProfileScreen`) is
  what then calls `sessionProvider.notifier.logout()` (purely local — clears stored tokens, no
  backend call, so it's safe to run after the account is already deleted server-side) and
  navigates to `/login` — the dialog itself never does either. A "Delete My Account" `TextButton`
  sits below the existing "Logout" button on both apps' Profile screens, styled muted/secondary
  rather than alarming red (unlike Logout) — the warning lives inside the dialog, not the
  button's own color.

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

### Requirement Duration (organisation requirements only)
`short_term` ("Short Term"), `long_term` ("Long Term") — `organisation_requirements.duration_type`, org-set at creation (`CreateOrganisationRequirementDto.duration_type`, required) and editable afterward by both the org itself (`UpdateMyOrganisationRequirementDto`) and admin (`AdminEditOrganisationRequirementDto`). Distinct from Individual's 4-value `Care Duration` enum above — organisation requirements have no per-requirement city/area/start-date at all (inherited from the org's own registered location), so this is the only scheduling-adjacent field they carry.

### Job Application Status
applied, rejected, accepted, completed — `accepted` is admin-only (see "Job/Application Flow" below); a caregiver can only ever set `applied`/`rejected` on their own application via apply, and `completed` via the separate per-job complete endpoint (`accepted` → `completed` only, see "Job/Application Flow").

### Duty Type
Field labeled "Hours Care Needed" in the admin-web UI (underlying field/column name unchanged: `duty_type`). Exactly 3 fixed shifts — no "other", and no separately admin-entered start/end time; the shift's timing is implied by which one is picked (the backend derives and stores `start_time`/`end_time` from `duty_type`):
- `live_in` — "24Hrs - Live In" (no fixed start/end time)
- `day_duty` — "12Hrs Day Shift (8am to 8pm)"
- `night_duty` — "12Hrs Night Shift (8pm to 8am)"

**nursenow-app's Individual Post/Edit Requirement forms show a ⓘ info button next to "Hours Care
Needed"** (`DutyRequirementsInfoButton`, `apps/justheal-app/lib/patient_hospital/features/
individual/widgets/duty_requirements_button.dart`) — tapping it opens a dialog listing what the patient/family must
arrange for the nurse under whichever shift is currently selected (bedding/meals for Live-In,
meals for Day/Night shift, gloves/masks/supplies, no cooking or household chores, etc. — a fixed
per-shift bullet list). Disabled (greyed out) until a shift is actually picked, since the content
is entirely shift-specific. **This content is static, hardcoded client-side, and NOT
admin-editable** — unlike Rate Card/Scope of Work, there's no backend model or admin screen behind
it, since it wasn't requested and the content is fixed operational policy, not care-need guidance.
NurseNow-Individual-specific — not shown on admin-web's job form or Organisation's posting screen.

### Frequency of Care
Required single-select on a job, alongside Duty Type/Hours Care Needed: `daily` ("Daily"), `monthly` ("Monthly"). Visible to caregivers on the job card same as every other requirement field.

### Care Duration
`few_days` ("Need for few Days"), `few_weeks` ("Need for Few Weeks"), `few_months` ("Need for Minimum a Month"), `long_term` ("Need for Long Term") — `jobs.care_duration` (migration 056). Required single-select, "Duration Care is Needed", shown directly below "Preferred Start Date" in nursenow-app's Individual Post/Edit Requirement forms — only the posting individual ever sets it, never admin (see "NurseNow" above). Nullable at the DB level (admin-posted jobs and every row that predates this column leave it `null`); visible read-only wherever a job's other requirement fields are shown once set (caregiver-app's `JobDetailCard`, admin-web's `JobReadOnlyDetailDialog`, nursenow-app's own `JobsPostedScreen`). **Picking `few_days`/`few_weeks` shows a purely-advisory warning right below the dropdown** (`_showShortTermDurationWarning`, same amber warning-container styling and never-blocks-submission convention as the gender/language/religion preference warnings on the same form) — "Short-term requirement / Many nurses do not accept short-term assignments...", suggesting the family edit to `few_months` ("Need for Minimum a Month") later if they get few/no applicants. `few_months`/`long_term` show no warning.

### Mobility — removed from the product entirely
The old `walks_independently`/`walks_with_assistance`/`uses_walker`/`uses_wheelchair`/`bedridden`
enum and its backing `care_receivers.mobility` column (migration 053) no longer exist — not
collected, stored, or displayed anywhere (admin-web's job posting/edit form and read-only detail
view, caregiver-app's job card, nursenow-app's Post/Edit Requirement forms, or the API). Removed
alongside NurseNow's Post/Edit Requirement restructure into "Patient Details"/"Care Preferences"
sections (see "NurseNow" above) — CARE_RECEIVER_DEFAULTS in `jobs.service.ts` no longer has a
mobility entry.

### Communication — removed from the product entirely
The old `verbal`/`difficulty_communicating`/`sign_language` enum (labels "Can Speak/Communicate"/
"Can NOT Speak"/"Communicate via Sign Languages") and its backing `care_receivers.communication`
column (migration 062) no longer exist — not collected, stored, or displayed anywhere (admin-web's
job posting/edit form and read-only detail view, caregiver-app's job card, nursenow-app's Post/Edit
Requirement forms, or the API). It had already been dropped from admin-web's form earlier (silently
defaulted server-side to `verbal` via `CARE_RECEIVER_DEFAULTS` in `jobs.service.ts`, which no longer
exists either now that this was its only remaining entry), so removing it outright was simply
finishing a removal that had already started — caregiver-app's job card no longer shows the
resulting "Can Speak/Communicate" tag, which had become meaningless once nothing could ever set it
to anything else.

### Feeding Type
`oral_feeding` ("Oral feeding"), `tube_feeding` ("Tube feeding"), `others` ("Others (Cannula etc.)")
— migration 057. Previously 4 values (`oral_independent`/`oral_needs_assistance`/`tube_feeding`/
`oral_and_tube`); `oral_independent` and `oral_needs_assistance` were merged into the single
`oral_feeding` (the independent-vs-needs-assistance distinction is no longer tracked), and
`oral_and_tube` was replaced by `others` — a different meaning (any non-oral/non-tube feeding
need, e.g. cannula), not a rename. `feeding_type` is a single required VARCHAR CHECK column on
`care_receivers` (unlike `toilet_assistance`, which has no DB-level CHECK), so the migration both
updates the constraint and backfills every existing row (`oral_independent`/`oral_needs_assistance`
→ `oral_feeding`, `oral_and_tube` → `others`) in the same statement — verified no production data
existed on any of the removed values at migration time. **Mandatory on every form that collects
it** (admin-web's job posting/edit form and nursenow-app's Post/Edit Requirement screens, labeled
"Feeding/Medicine Assistance (Mandatory)") — `CareReceiverDto.feeding_type` is hard-required at the
DTO layer (`@IsIn`, no `@IsOptional()`), a real change from the old "optional, defaults to
`oral_feeding` when omitted" behavior; `CARE_RECEIVER_DEFAULTS` no longer has a `feeding_type`
entry since every request is now guaranteed to supply it.

### Medical Assistance — removed from the product entirely
The old "Medicine" multi-select (medication_reminders/medication_administration/insulin_administration/other_injections/other) and its backing `care_receivers.medical_assistance` column (migration 050) no longer exist — not collected, stored, or displayed anywhere (admin-web's job posting form, caregiver-app's job card, nursenow-app's requirement form, or the API). Superseded by the expanded Medical Condition list below, which now covers most of the same ground (BP, Oxygen support, Insulin administration support, Injection support, Cannula care, Catheter care, Nebulisation support).

### Medical Condition (multi-select)
cancer, stroke, brain_injury, dementia_alzheimers, parkinsons, heart_condition, kidney_disease_dialysis, diabetes, colostomy, paralysis, tb, bp, oxygen_support, insulin_administration_support, injection_support, cannula_care, catheter_care, nebulisation_support, other. When `other` is selected, admin-web reveals an optional free-text field ("Please describe the other condition") stored as `care_receivers.medical_condition_other`; sent alongside — not instead of — the selected values. Unconditionally optional server-side (no cross-field validation tying it to `other` being selected). Visible to caregivers on the job card as "Other condition: <text>". **nursenow-app's individual posting/edit forms make this field mandatory**, via a UI-only `none` sentinel (never sent to the backend — mutually exclusive with every real condition, same pattern as the Language Preference "No Preference" sentinel): it's the first chip, checked by default, and picking it clears `has_medical_condition`/`medical_conditions` entirely rather than sending an actual `none` value. Admin-web's own job posting form is unchanged — still an optional toggle, not mandatory.

### Toilet Assistance (single-select)
`independent` ("Independent/minimal support"), `diapers_bedside_support` ("Diapers/bedside
support"), `uses_catheter` ("Catheter support"), `others` ("Others") — migration 057. Previously 6
values (`uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`others`/
`independent`); `uses_diapers` and `uses_bed_pan` were merged into the single
`diapers_bedside_support`, and `complete_toileting_assistance` was dropped entirely with no
replacement. `independent`/`uses_catheter`/`others` keep their original keys (only `uses_catheter`
and `independent` picked up new display labels — "Catheter support" and "Independent/minimal
support" respectively). **Now a mandatory single-select dropdown, not an optional multi-select
chip group** (admin-web's job posting/edit form and nursenow-app's Post/Edit Requirement screens,
labeled "Toilet Assistance (Mandatory)") — `care_receivers.toilet_assistance` is still a JSONB
array column with no DB-level CHECK (unchanged storage shape, so a single choice is submitted as a
1-element array), but `CareReceiverDto.toilet_assistance` is now hard-required and capped at
exactly one element (`@ArrayNotEmpty()` + `@ArrayMaxSize(1)`, no `@IsOptional()`) — a real change
from the old "optional multi-select, defaults to `[independent]` when omitted" behavior;
`CARE_RECEIVER_DEFAULTS` no longer has a `toilet_assistance` entry since every request is now
guaranteed to supply exactly one value. **Behavior of "Others" is unchanged**: selecting it still
reveals the same optional free-text field ("Please describe the other toilet assistance") stored
as `care_receivers.toilet_assistance_other`; same pattern as `medical_condition_other` above (sent
alongside the selected value, unconditionally optional, visible to caregivers as "Other toilet
assistance: <text>"). Both this and Feeding Type are shared enums — admin-web's own job
posting/edit form and caregiver-app's job card pick up every change automatically (they iterate
`ToiletAssistance.all`/`FeedingType.all` and `.displayNames`, no per-app hardcoded option list) —
the mandatory-single-select change described here applies identically everywhere a job is posted
or edited, not just nursenow-app's Post/Edit Requirement forms; caregiver-app's job card is
read-only display only and needed no changes.

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
