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
- **Job/Application Flow:** Admin posts a job describing the care receiver's needs — UI section labeled **"About Patient"** (the underlying `care_receivers` table/model keeps its original name; only the admin-web display label changed) — covering patient age/gender/weight, mobility, communication, feeding, toilet assistance (single-select: `uses_diapers`/`uses_bed_pan`/`uses_catheter`/`complete_toileting_assistance`/`none`), medical assistance/conditions, and vital monitoring (Yes/No; if Yes, multi-select which vitals: blood pressure/blood sugar/oxygen-SpO₂/temperature/pulse/other) — plus duty details (city, area, duty type — one of exactly 3 fixed shifts, see "Duty Type" below, no separately admin-entered start/end time — and start date) and soft caregiver preferences: language preference is **multi-select** (`languages`, a non-empty array — not a single value), gender and religion are single-select (all three are just informational tags, never used as a filter). Preferred religion offers `hindu`/`muslim`/`christian` only — **`others` is excluded** from this preference (it remains a valid value for a caregiver's own religion at registration, just not offered as a job's stated preference). The job's free-text field (`description`) is labeled in the UI as "More details you want to share about patient or requirement which can help caregiver to decide." A `care_receivers` row is created 1:1 with each job (not an independently reusable/searchable entity yet — a future "Patient" app will eventually supply real care-receiver identity data; this only captures the care-needs description). Caregivers **apply** or **reject** (`POST /caregiver/jobs/:id/apply`) — there's no "ask for more details" option. Admin reviews applicants, contacts them outside the app, then **accepts** one via `PATCH /admin/jobs/:jobId/applications/:applicationId` — this is the offer confirmation, not a separate in-app caregiver acceptance step. Accepting closes the job (`status = 'closed'`, no more applications) and sets that caregiver's `verification_status` to `assigned`. Admin can later reject that same accepted application to reopen the job and set the caregiver back to `available`. Other still-`applied` applications on a job are left untouched when one gets accepted — not auto-rejected.
- **Profile edits don't auto-reset status for `available`/`unavailable` caregivers**, with one exception: changing phone number or re-uploading Aadhaar is identity-sensitive and sends them back to `pending_call` (see transition matrix). Every other edit (age, languages, highest_qualification, preferred_cities, login code/PIN, selfie/qualification/other document re-uploads) only flags `has_pending_edits = true` for admin review, status untouched. **For a `rejected` caregiver, this is different: any edit at all — not just identity-sensitive ones — automatically resubmits them** (sends status back to `pending_call`). There's no separate "resubmit" action; editing the flagged field(s) normally is the resubmission.
- **Caregivers cannot edit their own full_name or gender.** Both are locked from self-edit past registration — only admins can change them (via the admin edit endpoint). **Religion** follows the same rule: set once at registration, it's locked from the self-edit endpoint (`PATCH /caregiver/profile`) — only admins can change it from that point on. Every other field remains caregiver-editable via self-edit.

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
- Show bottom navigation at all times after registration. Caregivers can browse jobs even before approval (motivates onboarding).
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
assigned → available                              (admin: unassign — work completed)
available → pending_call                          (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
unavailable → pending_call                        (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
rejected → pending_call                           (system: any caregiver edit at all — auto-resubmit, no separate "resubmit" action)
```

**Notes:**
- `available` = verified + taking work. Green icon. Can respond to jobs.
- `unavailable` = verified but NOT taking work. Green icon (still verified) but greyed out. Cannot respond to jobs, cannot be assigned.
- `assigned` = currently working. Cannot toggle availability (admin must unassign first).
- Daily push at 8 AM reminds available/unavailable caregivers to confirm status. No response = no change.

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
Exactly 3 fixed shifts — no "other", and no separately admin-entered start/end time; the shift's timing is implied by which one is picked (the backend derives and stores `start_time`/`end_time` from `duty_type`):
- `live_in` — "24Hrs - Live In" (no fixed start/end time)
- `day_duty` — "12Hrs Day Shift (8am to 8pm)"
- `night_duty` — "12Hrs Night Shift (8pm to 8am)"

### Mobility
walks_independently, walks_with_assistance, uses_walker, uses_wheelchair, bedridden

### Communication
verbal, difficulty_communicating, sign_language, other_non_verbal

### Feeding Type
oral_independent, oral_needs_assistance, tube_feeding, oral_and_tube

### Medical Assistance (multi-select)
medication_reminders, medication_administration, insulin_administration, other_injections, other

### Medical Condition (multi-select)
cancer, stroke, brain_injury, dementia_alzheimers, parkinsons, heart_condition, kidney_disease_dialysis, diabetes, colostomy, paralysis, other

### Toilet Assistance
uses_diapers, uses_bed_pan, uses_catheter, complete_toileting_assistance, none

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
