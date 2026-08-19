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
- **Database:** Supabase PostgreSQL (used as a standard Postgres, no RLS for app tables).
- **Storage:** Supabase Storage with signed URLs (1hr expiry). Files at `{profile_id}/filename.ext`.
- **Realtime:** Supabase Realtime for admin dashboard only. Caregivers use FCM push.
- **Email:** Nodemailer + Gmail SMTP (vitacasahealthindia@gmail.com). Plain text only in V1.
- **No OTP:** Phone login has no OTP. Phone verified via office call.
- **Caregiver login:** Phone + 4-digit code, always. The code is set at registration and is required for every login from the first session onward. There is no phone-only login endpoint.
- **There is no separate "Advanced Details" step.** Everything is collected in one registration (`POST /auth/register`): basic info, religion, highest qualification, and terms acceptance, plus documents uploaded via their own endpoints immediately after (selfie and Aadhaar are mandatory; qualification document and up to 3 "other" documents are optional). Religion is required at registration and locked from self-edit afterward; highest_qualification, preferred_cities (optional at registration), preferred_duty_types, min_salary_per_day, min_salary_per_month, and documents all remain editable afterward via the single self-edit endpoint (`PATCH /caregiver/profile`) or document re-upload endpoints.
- **father_name, father_phone, current_address, and notes have been removed from the product entirely** — no longer collected, stored, or displayed anywhere (caregiver-app, admin-web, or the database).
- **Admin-assigned work types, service modes, and salary have been removed from the product entirely**, along with the two admin-notes rate fields (Rate — 24Hrs Live-In, Rate — 12Hrs PG) — no longer collected, stored, or displayed anywhere. `admin_notes` still has `internal_notes` and `availability_remarks`. `WorkType`/`ServiceMode`/`SalaryRanges` are gone too — a job posting is no longer built around a single "work type" category (see "Job/Application Flow" below).
- **Job/Application Flow:** Admin posts a job describing the care receiver's needs, grouped in the admin-web posting/edit form into two clearly labeled sections (the underlying `care_receivers` table/model keeps its original name — only these are UI display labels). **Only `age`/`gender`/`weight_kg` are hard-required on the care receiver** (plus `city`/`area`/`start_date` on the job itself — `area` was previously optional free text, now required; `start_date`, labeled "Preferred Start Date", was previously optional, now required — while the free-text `description` field moved the other way, from required to optional, see below); every other care-receiver field — `mobility`, `communication`, `feeding_type`, `medical_assistance`, `has_medical_condition`, `toilet_assistance`, `requires_vital_monitoring` — is optional on the form and, left unselected (or submitted empty), is defaulted server-side (`CARE_RECEIVER_DEFAULTS` in `jobs.service.ts`) to a real, explicit value: `mobility` → `walks_independently`, `communication` → `verbal`, `feeding_type` → `oral_independent`, `medical_assistance` → `[medication_reminders]`, `has_medical_condition` → `false`, `toilet_assistance` → `[independent]`, `requires_vital_monitoring` → `false`. These defaults are persisted (not left null), so they show up identically to an explicit selection everywhere — caregiver-app's job card and admin-web's edit-prefill both just render whatever is stored, with no special "defaulted" handling needed. **"About Patient"** (age, gender, weight, mobility, communication, feeding, "Medicine" — medical assistance multi-select, has-medical-condition + conditions, toilet assistance — multi-select, admin can pick more than one: `uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`others`/`independent` — and vital monitoring: Yes/No, if Yes multi-select which vitals: blood pressure/blood sugar/oxygen-SpO₂/temperature/pulse/other — this was previously split into a separate "About Patient Condition" section; that section no longer exists, everything lives under "About Patient" now), and **"About Nurse/Caregiver Requirement"** (salary, "Hours Care Needed" — one of exactly 3 fixed shifts, see "Duty Type" below, no separately admin-entered start/end time — Frequency of Care (`daily`/`monthly`, required), "Preferred Start Date" (required), and soft caregiver preferences: language preference is **multi-select** (`languages`, a non-empty array — not a single value), gender and religion are single-select; preferred religion offers `hindu`/`muslim`/`christian` only — **`others` is excluded**, it remains valid for a caregiver's own religion at registration, just not offered as a job preference; preferred religion (and language) stay purely informational tags never used as a filter, but **preferred gender is enforced server-side** — `GET /caregiver/jobs` only returns jobs whose `preferred_gender` is unset (no preference) or matches the requesting caregiver's own `caregiver_profiles.gender`, so a caregiver never sees a job posted for the other gender; this filtering happens in `JobsRepository.listActiveForCaregiver`, not in the caregiver-app UI). Job Location (city, area — both required) is its own section above these two; the free-text `description` field (label shortened to "More details you want to share about patient" — previously required, now optional) sits below them. A `care_receivers` row is created 1:1 with each job (not an independently reusable/searchable entity yet — a future "Patient" app will eventually supply real care-receiver identity data; this only captures the care-needs description). **Every one of these details is visible to caregivers too** — `GET /caregiver/jobs` joins in the full `care_receiver` (not just `GET /admin/jobs/:id`), and caregiver-app's job card renders it under the same two section labels, so a caregiver sees the full patient/condition/requirement picture directly on the jobs list, no separate detail screen needed. Caregivers **apply** or **reject** (`POST /caregiver/jobs/:id/apply`) — there's no "ask for more details" option. Admin reviews applicants, contacts them outside the app, then **accepts** one via `PATCH /admin/jobs/:jobId/applications/:applicationId` — this is the offer confirmation, not a separate in-app caregiver acceptance step. Accepting closes the job (`status = 'closed'`, no more applications) and sets that caregiver's `verification_status` to `assigned`. Admin can later reject that same accepted application to reopen the job and set the caregiver back to `available`. Other still-`applied` applications on a job are left untouched when one gets accepted — not auto-rejected. Admin can view a job's full details and edit any field (via `PATCH /admin/jobs/:id`, same shape/validation as create) — same job id, existing applications untouched regardless of status (including one with an accepted/assigned applicant). If the job was `closed` when edited, saving the edit also **reposts** it: status flips back to `active` and the "New Job" push re-broadcasts to all caregivers; editing an already-`active` job does not resend that push. **Once accepted, the caregiver can see and contact whoever posted the job** — `GET /caregiver/jobs/assigned` includes `job_poster: { full_name, phone }`, the posting admin's contact info, per job. This is deliberately scoped to that one endpoint only — never on the browse list (`GET /caregiver/jobs`) — since admin contact info is only shared once there's an actual accepted engagement, not to every caregiver browsing jobs. Shown in two places in caregiver-app: always on the MyJobs tab (the durable historical record — one contact card per job), and also on the Profile tab but only while `verification_status` is currently `assigned` (Profile fetches `GET /caregiver/jobs/assigned` itself, gated on that status, so it doesn't keep showing a past job's poster(s) once the caregiver is available again). **A caregiver can be accepted onto more than one job at once** — nothing in the eligibility check (`available`/`assigned` are both apply-eligible) or in `decideApplication` prevents a second acceptance while already `assigned`. `GET /caregiver/jobs/assigned` therefore returns an **array**, not a single job/null — every job the caregiver currently holds an `accepted` or `completed` `job_applications` row for, oldest-decision-first by `updated_at`; this is the durable history the MyJobs tab renders (one card per job), so a completed job stays listed rather than disappearing. Each accepted job in MyJobs gets its own **"Mark Complete"** button, calling `POST /caregiver/jobs/:id/complete` (caregiver-only, no body) — this flips just that one `job_applications` row to a fourth status, `completed` (with a `completed_at` timestamp, mirroring `applied_at`/`accepted_at`/`rejected_at`), and only drops `caregiver_profiles.verification_status` back to `available` once **no other `accepted` applications remain**; if the caregiver still holds another active job, `verification_status` stays `assigned`. `JOB_008` covers every case where completion doesn't apply — never applied to that job, still `applied`, already `rejected`, or already `completed`. The job itself is never reopened by completion (stays `closed`, same as today's mark-available philosophy). Because of this, the Profile tab's single global "Available for Jobs" button (`POST /caregiver/mark-available`) **no longer covers `assigned → available`** — with several jobs potentially active at once it can't say which one it means — see the Verification Status Transitions notes below. **The caregiver's own application (`GET /caregiver/jobs`'s `my_application`) carries the real per-transition timeline** (`applied_at`/`accepted_at`/`rejected_at`, each null until that transition happens), not just the bare current `status` — a caregiver's own self-decline and an admin un-accepting them both land on `status = 'rejected'` in the DB, and `decided_by_admin` (derived from `decided_by IS NOT NULL`) is what tells them apart; caregiver-app shows "Declined: <date>" for the former and "Declined by employer: <date>" for the latter, alongside "Applied: <date>" and "Accepted: <date>" (if it happened) — never a bare unqualified "You declined". **Admin-web gets the same timeline, plus who decided it**: each row in `GET /admin/jobs/:id`'s `applications` array carries `applied_at`/`accepted_at`/`rejected_at` and `decided_by_name` (the deciding admin's `full_name`, resolved via a `LEFT JOIN users` on `decided_by` — `null` while `status = 'applied'` or on a caregiver self-decline). The Job Applicants dialog renders this under each applicant as "Applied: <date>", "Accepted: <date> by <admin>", and/or "Declined by <admin>: <date>".
- **admin-web's Jobs list opens read-only by default, not straight into an editable form.** Tapping a job row (anywhere except its action buttons) opens `JobReadOnlyDetailDialog` — every field as plain text, grouped the same as the Post/Edit form (Job Location/Hours-Care-Needed/Frequency/Salary/etc., then About Patient) — with its own **Edit** button that hands off to the existing `_JobFormDialog` edit flow. The row's own explicit **Edit** `TextButton` still jumps straight into the editable form as a shortcut, unchanged; the read-only view is an additional entry point, not a replacement for it.
- **Job number, salary, and apply-by urgency:** Every job has a `job_number` (short sequential integer, auto-assigned, distinct from the internal UUID `id`) shown as "Job #<n>" at the top of the job card/row on both admin-web and caregiver-app — a human-friendly id both sides can reference. Admin sets a single required `salary_amount` when posting or editing a job; its unit follows the job's `frequency_of_care` (₹/day for `daily`, ₹/month for `monthly`), and this dynamic unit is shown everywhere the figure appears — admin-web's form label and job list row, and caregiver-app's job card, which shows it highlighted prominently at the top. Every job also carries `posted_at` (starts equal to `created_at`, but is bumped to "now" only when a `closed` job is edited-and-reposted — a plain edit of an already-`active` job leaves it untouched) driving a caregiver-facing **3-day apply-by urgency window**: `posted_at + 3 days`, shown as "Posted: <date>" plus a days-left message ("X days left to apply" / "Last day..." / "Application window closed"). This is purely informational — it does not block applying, and the job itself is not auto-closed when the window passes; admin must still close (or let it be) manually.
- **Caregiver job search preferences:** on top of `preferred_cities`, a caregiver can set `preferred_duty_types` (multi-select from the same 3 fixed shifts as a job's `duty_type` — stored in a `caregiver_preferred_duty_types` junction table, same many-to-many pattern as `caregiver_preferred_cities`), `min_salary_per_day`, and `min_salary_per_month` (both optional integers on `caregiver_profiles`) via the same self-edit endpoint (`PATCH /caregiver/profile`) — editable anytime, no admin approval needed, never touches `verification_status`. All four dynamically filter `GET /caregiver/jobs` (in `JobsRepository.listActiveForCaregiver`, alongside the existing `preferred_gender` filter): a job is hidden unless its `city` is in the caregiver's `preferred_cities` (or that list is empty — no preference), its `duty_type` is in `preferred_duty_types` (or that list is empty), and its `salary_amount` meets the threshold for its own `frequency_of_care` — a `daily` job is only ever compared against `min_salary_per_day`, a `monthly` job only against `min_salary_per_month`, each independently nullable and never cross-applied to the other frequency. Filtering is read fresh from the caregiver's current profile on every request, so changing a preference takes effect on the very next job list fetch — there is no caching, no re-indexing step, and no separate "apply preferences" action. **In caregiver-app, all four preferences live on their own screen (`JobPreferencesScreen`), reached via a gear icon (`Icons.tune`) in the Jobs tab's app bar** — not on Edit Profile, which only carries an in-app pointer to the Jobs tab now that these moved. Saving pops back to the Jobs tab and immediately reloads the list so the new filtering is visible right away.
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
  `PATCH /individual/requirements/:jobId/applications/:applicationId` (accept/reject an
  applicant — ownership-checked, then delegates to the same `JobsService.decideApplication` admin
  uses), `PATCH /individual/profile/phone` / `PATCH /individual/profile/code` (self-service phone
  and 4-digit PIN change, reusing caregiver's `UpdatePhoneDto`/`UpdateCodeDto` — no re-review
  logic, since an individual account has no verification pipeline to send back for review).
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
- **Applicant review is forced one-at-a-time, not a free list.** With multiple caregivers applied
  to the same requirement, the patient/family sees the total count up front ("N candidates applied
  in total") but only the single oldest still-`applied` candidate at a time — Accept/Reject for
  that one only; the next undecided candidate isn't shown until this one is decided. Already-
  decided candidates (from this or an earlier session) stay visible below in a read-only history,
  including who was ultimately accepted, so that record is never lost once the requirement closes.
  **Rejecting an applicant requires a reason** — `job_applications.decline_reason` (added by
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
  `frequency_of_care`/`salary_amount`/`start_date` (admin-set on approval, same null-until-
  approved pattern as an Individual's posting). Created with `status: 'pending_review'`.
  **Unlike Individual, there is no one-live-requirement limit** — an org can have many
  simultaneous postings, since a hospital/rehab genuinely needs to fill several openings at
  once; this was a deliberate scope difference, not an oversight.
- **Admin approves via the same "edit with full shape" pattern as Individual**:
  `PATCH /admin/organisation-requirements/:id` (`UpdateOrganisationRequirementDto`, requiring
  `type_of_nurse`/`frequency_of_care`/`salary_amount`/`accommodation_provided`/
  `food_provided`, optional `start_date`/`special_skills`) transitions `pending_review` (or a
  `closed` requirement) to `active` and stamps `posted_at` — `start_date` is only ever
  persisted when `frequency_of_care === 'daily'` (null otherwise), enforced in
  `OrganisationRequirementsService.updateRequirement`, not a DB constraint. Admin can instead
  **reject** via `PATCH /admin/organisation-requirements/:id/reject` (`{ reason }`, reusing the
  same `RejectJobDto` Individual uses) — sets `status: 'closed'` + `rejection_reason`, only
  valid from `pending_review`.
- **Organisation-side endpoints** (`@Roles(UserRole.ORGANISATION)`, `src/organisation/`):
  `GET /organisation/me`, `POST /organisation/requirements`, `GET /organisation/requirements`
  (full history, not just current), `GET /organisation/requirements/:id/applications`,
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
- **admin-web:** two new sidebar tabs — **"Rehab/Hospitals"** (`/rehab-hospitals` →
  `OrganisationsListScreen`, mirrors `IndividualsListScreen` exactly: lists every organisation
  account via `GET /admin/organisations` with the same two block levers,
  `PATCH /admin/organisations/:id/block` `{ level: 'job_posting' | 'full', reason }` /
  `.../unblock`) and **"Organisation Requirements"** (`/rehab-requirements` →
  `AdminOrganisationRequirementsScreen`, a dedicated screen — deliberately NOT folded into
  `AdminJobsScreen`, since organisation requirements are a wholly separate table/model — listing
  every requirement via `GET /admin/organisation-requirements` with Applicants (Accept/Reject per
  applicant, optional reason), Reject (pending_review only, reason-required dialog), and a single
  **Edit** action (dialog collecting Frequency of Care/Salary/optional Preferred Start Date when
  Daily is picked) that doubles as "Approve" from `pending_review` and as an ordinary edit from
  `active`/`closed` — admin can revisit and correct these same admin-set fields later, not just
  once at approval time; same `PATCH /admin/organisation-requirements/:id` endpoint either way,
  pre-filled with the requirement's current values when editing. Tapping a requirement row opens
  a read-only detail view first (every field as plain text) with its own Edit button into that
  same dialog — same "view, then optionally edit" pattern as `AdminJobsScreen`'s job rows.

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
unavailable → available                           (caregiver OR admin: "ready for work again")
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
- `POST /caregiver/mark-available` (caregiver-only, no body; UI button label "Available for Jobs", shown on the Profile tab) now covers **only** `unavailable → available` — it no longer handles `assigned → available` (a caregiver can hold several accepted jobs, so a single global button can't say which one it means; the button is hidden entirely while `assigned`, see MyJobs' per-job "Mark Complete" above). Called while already `available` it's a no-op (`already_available: true` in the response, no DB write, no audit entry — the UI shows "You are already marked as available"); called from `pending_call` or `rejected` it 400s with `PROFILE_022` (a rejected caregiver must instead edit their profile, which auto-resubmits per the row above — there's no self-service path out of `pending_call`). The endpoint itself still accepts being called from `assigned` server-side (unchanged, blind flip) — only the caregiver-app UI stopped exposing that path.
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
registered_nurse, staff_nurse, icu_nurse, icu_trained_attendant, gnm_nurse, anm_nurse, gda, patient_care_assistant, home_health_aide, physiotherapist, elderly_care_attendant, post_operative_care_nurse. Validated at the DTO layer (`@IsIn`), not a DB `CHECK`, so the list can be adjusted without a migration. Distinct from `Qualification` (a caregiver's own self-reported credential) — this is the category an organisation requests when posting a requirement.

### Job Application Status
applied, rejected, accepted, completed — `accepted` is admin-only (see "Job/Application Flow" below); a caregiver can only ever set `applied`/`rejected` on their own application via apply, and `completed` via the separate per-job complete endpoint (`accepted` → `completed` only, see "Job/Application Flow").

### Duty Type
Field labeled "Hours Care Needed" in the admin-web UI (underlying field/column name unchanged: `duty_type`). Exactly 3 fixed shifts — no "other", and no separately admin-entered start/end time; the shift's timing is implied by which one is picked (the backend derives and stores `start_time`/`end_time` from `duty_type`):
- `live_in` — "24Hrs - Live In" (no fixed start/end time)
- `day_duty` — "12Hrs Day Shift (8am to 8pm)"
- `night_duty` — "12Hrs Night Shift (8pm to 8am)"

### Frequency of Care
Required single-select on a job, alongside Duty Type/Hours Care Needed: `daily` ("Daily"), `monthly` ("Monthly"). Visible to caregivers on the job card same as every other requirement field.

### Mobility
walks_independently, walks_with_assistance, uses_walker, uses_wheelchair, bedridden

### Communication
Exactly 3 options (`other_non_verbal` dropped):
- `verbal` — "Can Speak/Communicate"
- `difficulty_communicating` — "Can NOT Speak"
- `sign_language` — "Communicate via Sign Languages"

### Feeding Type
oral_independent, oral_needs_assistance, tube_feeding, oral_and_tube

### Medical Assistance (multi-select)
medication_reminders ("Medicine Reminders"), medication_administration ("Oral Medicine Administration"), insulin_administration, other_injections, other ("Others/Cannula/Tube")

### Medical Condition (multi-select)
cancer, stroke, brain_injury, dementia_alzheimers, parkinsons, heart_condition, kidney_disease_dialysis, diabetes, colostomy, paralysis, tb, other. When `other` is selected, admin-web reveals an optional free-text field ("Please describe the other condition") stored as `care_receivers.medical_condition_other`; sent alongside — not instead of — the selected values. Unconditionally optional server-side (no cross-field validation tying it to `other` being selected). Visible to caregivers on the job card as "Other condition: <text>".

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
