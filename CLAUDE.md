# VitaCare — AI Development Context

## Project Overview

VitaCare is an in-home caregiver onboarding platform by VitaCasaHealth (vitacasahealth.in).
- **V1 scope:** Caregiver registration + admin verification. No booking, payments, or family features.
- **Monorepo:** All apps and shared packages in one repository.

## Architecture

| App | Path | Tech |
|-----|------|------|
| Backend API | `apps/api/` | NestJS 10.x, Node.js 20 LTS, TypeScript |
| Caregiver Mobile | `apps/caregiver-app/` | Flutter 3.19+, Dart, Riverpod |
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
- **There is no separate "Advanced Details" step.** Everything is collected in one registration (`POST /auth/register`): basic info, religion, highest qualification, and terms acceptance, plus documents uploaded via their own endpoints immediately after (selfie and Aadhaar are mandatory; qualification document and up to 3 "other" documents are optional). Religion is required at registration and locked from self-edit afterward; highest_qualification, preferred_cities (optional at registration), and documents all remain editable afterward via the single self-edit endpoint (`PATCH /caregiver/profile`) or document re-upload endpoints.
- **father_name, father_phone, current_address, and notes have been removed from the product entirely** — no longer collected, stored, or displayed anywhere (caregiver-app, admin-web, or the database).
- **Admin-assigned work types, service modes, and salary have been removed from the product entirely**, along with the two admin-notes rate fields (Rate — 24Hrs Live-In, Rate — 12Hrs PG) — no longer collected, stored, or displayed anywhere. `admin_notes` still has `internal_notes` and `availability_remarks`. `WorkType`/`ServiceMode`/`SalaryRanges` are gone too — a job posting is no longer built around a single "work type" category (see "Job/Application Flow" below).
- **Job/Application Flow:** Admin posts a job describing the care receiver's needs, grouped in the admin-web posting/edit form into two clearly labeled sections (the underlying `care_receivers` table/model keeps its original name — only these are UI display labels). **Only `age`/`gender`/`weight_kg` are hard-required on the care receiver** (plus `city`/`area` on the job itself — `area` was previously optional free text, now required); every other care-receiver field — `mobility`, `communication`, `feeding_type`, `medical_assistance`, `has_medical_condition`, `toilet_assistance`, `requires_vital_monitoring` — is optional on the form and, left unselected (or submitted empty), is defaulted server-side (`CARE_RECEIVER_DEFAULTS` in `jobs.service.ts`) to a real, explicit value: `mobility` → `walks_independently`, `communication` → `verbal`, `feeding_type` → `oral_independent`, `medical_assistance` → `[medication_reminders]`, `has_medical_condition` → `false`, `toilet_assistance` → `[independent]`, `requires_vital_monitoring` → `false`. These defaults are persisted (not left null), so they show up identically to an explicit selection everywhere — caregiver-app's job card and admin-web's edit-prefill both just render whatever is stored, with no special "defaulted" handling needed. **"About Patient"** (age, gender, weight, mobility, communication, feeding, "Medicine" — medical assistance multi-select, has-medical-condition + conditions + free-text info, toilet assistance — multi-select, admin can pick more than one: `uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`others`/`independent` — and vital monitoring: Yes/No, if Yes multi-select which vitals: blood pressure/blood sugar/oxygen-SpO₂/temperature/pulse/other — this was previously split into a separate "About Patient Condition" section; that section no longer exists, everything lives under "About Patient" now), and **"About Nurse/Caregiver Requirement"** (salary, "Hours Care Needed" — one of exactly 3 fixed shifts, see "Duty Type" below, no separately admin-entered start/end time — Frequency of Care (`daily`/`monthly`, required), "Preferred Start Date", and soft caregiver preferences: language preference is **multi-select** (`languages`, a non-empty array — not a single value), gender and religion are single-select, all just informational tags never used as a filter; preferred religion offers `hindu`/`muslim`/`christian` only — **`others` is excluded**, it remains valid for a caregiver's own religion at registration, just not offered as a job preference). Job Location (city, area — both required) is its own section above these two; the free-text `description` field ("More details you want to share about patient or requirement which can help caregiver to decide") sits below them. A `care_receivers` row is created 1:1 with each job (not an independently reusable/searchable entity yet — a future "Patient" app will eventually supply real care-receiver identity data; this only captures the care-needs description). **Every one of these details is visible to caregivers too** — `GET /caregiver/jobs` joins in the full `care_receiver` (not just `GET /admin/jobs/:id`), and caregiver-app's job card renders it under the same two section labels, so a caregiver sees the full patient/condition/requirement picture directly on the jobs list, no separate detail screen needed. Caregivers **apply** or **reject** (`POST /caregiver/jobs/:id/apply`) — there's no "ask for more details" option. Admin reviews applicants, contacts them outside the app, then **accepts** one via `PATCH /admin/jobs/:jobId/applications/:applicationId` — this is the offer confirmation, not a separate in-app caregiver acceptance step. Accepting closes the job (`status = 'closed'`, no more applications) and sets that caregiver's `verification_status` to `assigned`. Admin can later reject that same accepted application to reopen the job and set the caregiver back to `available`. Other still-`applied` applications on a job are left untouched when one gets accepted — not auto-rejected. Admin can view a job's full details and edit any field (via `PATCH /admin/jobs/:id`, same shape/validation as create) — same job id, existing applications untouched regardless of status (including one with an accepted/assigned applicant). If the job was `closed` when edited, saving the edit also **reposts** it: status flips back to `active` and the "New Job" push re-broadcasts to all caregivers; editing an already-`active` job does not resend that push. **Once accepted, the caregiver can see and contact whoever posted the job** — `GET /caregiver/jobs/assigned` includes `job_poster: { full_name, phone }`, the posting admin's contact info. This is deliberately scoped to that one endpoint only — never on the browse list (`GET /caregiver/jobs`) — since admin contact info is only shared once there's an actual accepted engagement, not to every caregiver browsing jobs. Shown in two places in caregiver-app: always on the MyJobs tab (the durable historical record), and also on the Profile tab but only while `verification_status` is currently `assigned` (Profile fetches `GET /caregiver/jobs/assigned` itself, gated on that status, so it doesn't keep showing a past job's poster once the caregiver is available again). **The caregiver's own application (`GET /caregiver/jobs`'s `my_application`) carries the real per-transition timeline** (`applied_at`/`accepted_at`/`rejected_at`, each null until that transition happens), not just the bare current `status` — a caregiver's own self-decline and an admin un-accepting them both land on `status = 'rejected'` in the DB, and `decided_by_admin` (derived from `decided_by IS NOT NULL`) is what tells them apart; caregiver-app shows "Declined: <date>" for the former and "Declined by employer: <date>" for the latter, alongside "Applied: <date>" and "Accepted: <date>" (if it happened) — never a bare unqualified "You declined". **Admin-web gets the same timeline, plus who decided it**: each row in `GET /admin/jobs/:id`'s `applications` array carries `applied_at`/`accepted_at`/`rejected_at` and `decided_by_name` (the deciding admin's `full_name`, resolved via a `LEFT JOIN users` on `decided_by` — `null` while `status = 'applied'` or on a caregiver self-decline). The Job Applicants dialog renders this under each applicant as "Applied: <date>", "Accepted: <date> by <admin>", and/or "Declined by <admin>: <date>".
- **Job number, salary, and apply-by urgency:** Every job has a `job_number` (short sequential integer, auto-assigned, distinct from the internal UUID `id`) shown as "Job #<n>" at the top of the job card/row on both admin-web and caregiver-app — a human-friendly id both sides can reference. Admin sets a single required `salary_monthly` (₹/month) when posting or editing a job; caregiver-app shows it highlighted prominently at the top of the job card. Every job also carries `posted_at` (starts equal to `created_at`, but is bumped to "now" only when a `closed` job is edited-and-reposted — a plain edit of an already-`active` job leaves it untouched) driving a caregiver-facing **3-day apply-by urgency window**: `posted_at + 3 days`, shown as "Posted: <date>" plus a days-left message ("X days left to apply" / "Last day..." / "Application window closed"). This is purely informational — it does not block applying, and the job itself is not auto-closed when the window passes; admin must still close (or let it be) manually.
- **Profile edits don't auto-reset status for `available`/`unavailable` caregivers**, with one exception: changing phone number or re-uploading Aadhaar is identity-sensitive and sends them back to `pending_call` (see transition matrix). Every other edit (age, languages, highest_qualification, preferred_cities, login code/PIN, selfie/qualification/other document re-uploads) only flags `has_pending_edits = true` for admin review, status untouched. **For a `rejected` caregiver, this is different: any edit at all — not just identity-sensitive ones — automatically resubmits them** (sends status back to `pending_call`). There's no separate "resubmit" action; editing the flagged field(s) normally is the resubmission.
- **Caregivers cannot edit their own full_name or gender.** Both are locked from self-edit past registration — only admins can change them (via the admin edit endpoint). **Religion** follows the same rule: set once at registration, it's locked from the self-edit endpoint (`PATCH /caregiver/profile`) — only admins can change it from that point on. Every other field remains caregiver-editable via self-edit.
- **Force-upgrade:** admin-web has an "App Versions" screen (any admin, not just super_admin) where an admin sets a `min_version` (and optional `store_url`/`update_message`) per platform (`android`/`ios`) in the `app_min_versions` table (one row per platform, seeded at `1.0.0`). The caregiver app checks `GET /app-versions/check?platform=&version=` (public, no auth) on every cold launch — before the splash screen even loads the session, via `AppVersionRepository.checkForUpdate()` — and if its own build (`PackageInfo.version`) is below `min_version`, shows a full-screen, non-dismissible `UpdateRequiredScreen` with the admin's `update_message` (or a generic default) and an "Update Now" button linking to `store_url`; nothing else in the app loads until the caregiver updates. Platform is determined via `defaultTargetPlatform` (not `dart:io Platform`, which doesn't compile for the web dev target this app is also tested against) — anything other than iOS is treated as `android`. The version check is deliberately **fail-open**: any error (network down, backend unreachable, malformed response) is caught and treated as "no update needed," since a broken check must never be able to lock every caregiver out. admin-web itself has no equivalent gate — it's a web app that just needs a browser reload to pick up a new deploy (see Firebase Hosting cache note), not a store-distributed binary.

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
- Show bottom navigation at all times after registration. Caregivers can browse jobs even before approval (motivates onboarding). 3 tabs: Profile, Jobs (browse/apply), MyJobs (the caregiver's own current/most-recent assigned+accepted job, from `GET /caregiver/jobs/assigned` — see "Job/Application Flow" below).
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
assigned → available                              (caregiver OR admin: caregiver self-service "Available for Jobs" one-click button, or admin: unassign — work completed)
available → pending_call                          (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
unavailable → pending_call                        (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
rejected → pending_call                           (system: any caregiver edit at all — auto-resubmit, no separate "resubmit" action)
```

**Notes:**
- `available` = verified + taking work. Green icon. Can respond to jobs.
- `unavailable` = verified but NOT taking work. Green icon (still verified) but greyed out. Cannot respond to jobs, cannot be assigned.
- `assigned` = currently working. Caregiver can self-unassign anytime via the one-click "Available for Jobs" button (`POST /caregiver/mark-available`) — admin doesn't have to unassign first. This only flips `caregiver_profiles.verification_status`; it deliberately does NOT touch the job or `job_applications` row (mirrors the admin override endpoint's scope), so the job stays closed and the application stays `accepted` as a historical record.
- `POST /caregiver/mark-available` (caregiver-only, no body; UI button label "Available for Jobs") is the single self-service action covering both `unavailable → available` and `assigned → available`: called while already `available` it's a no-op (`already_available: true` in the response, no DB write, no audit entry — the UI shows "You are already marked as available"); called from `pending_call` or `rejected` it 400s with `PROFILE_022` (a rejected caregiver must instead edit their profile, which auto-resubmits per the row above — there's no self-service path out of `pending_call`).
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
super_admin, admin, caregiver

### Job Status
active, closed

### Job Application Status
applied, rejected, accepted — `accepted` is admin-only (see "Job/Application Flow" below); a caregiver can only ever set `applied`/`rejected` on their own application.

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
