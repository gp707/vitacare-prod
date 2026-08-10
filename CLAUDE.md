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
- **Caregiver login:** Phone + 4-digit code, always. The code is set at registration (not deferred to advanced details) and is required for every login from the first session onward. There is no phone-only login endpoint.
- **Profile edits don't auto-reset status**, with one exception: changing phone number or re-uploading Aadhaar is identity-sensitive and sends an `available`/`unavailable` caregiver back to `pending_verification` (not from `in_process`/`assigned` — see transition matrix). Every other edit (gender, age, languages, login code/PIN, qualification, religion, parents' info, address, city, notes, selfie/profile picture, qualification/other document re-uploads) only flags `has_pending_edits = true` for admin review, status untouched.
- **Caregivers cannot edit their own full_name or gender.** Both are locked from self-edit past registration — only admins can change them (via the admin edit endpoint). **Religion** follows a narrower version of the same rule: it's caregiver-settable during Advanced Details submission and rejected-resubmission (`PUT /caregiver/profile/advanced`), but once set it's locked from the separate self-edit endpoint (`PATCH /caregiver/profile/advanced`) — only admins can change it from that point on. Every other basic/advanced field remains caregiver-editable via self-edit.

## Naming Conventions (STRICT)

| Context | Convention | Example |
|---------|-----------|---------|
| Database tables | snake_case | `caregiver_profiles` |
| Database columns | snake_case | `verification_status` |
| API endpoints | kebab-case | `/admin/caregivers/:id/call-verified` |
| API request/response fields | snake_case | `full_name` |
| NestJS files | kebab-case | `caregiver.controller.ts` |
| NestJS classes | PascalCase | `CaregiverController` |
| Flutter files | snake_case | `caregiver_profile_screen.dart` |
| Flutter classes | PascalCase | `CaregiverProfileScreen` |
| Flutter routes | kebab-case | `/advanced-details` |
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
- Do NOT expose admin notes or rates to caregiver-facing endpoints.
- Do NOT hardcode env values. Always use ConfigService.
- Do NOT store refresh tokens or codes in plain text. Store bcrypt hash.
- Do NOT validate file MIME types. Accept any file type, enforce 10MB max only.
- Do NOT use the Supabase service role key in client apps.
- Do NOT auto-reset verification status on profile edit — EXCEPT changing phone or re-uploading Aadhaar, which resets `available`/`unavailable` back to `pending_verification` (never from `in_process`/`assigned`).
- Do NOT allow status transitions not in the transition matrix — EXCEPT via the admin status-override endpoint (`PATCH /admin/caregivers/:id/status`), which is deliberately unrestricted: admin can set any caregiver to any status from any current status. Caregiver-initiated and system-triggered transitions (phone/Aadhaar change, availability toggle, resubmission) still must follow the matrix below.
- Do NOT return more than 100 items per page.
- Do NOT allow caregivers to modify work types or salary. Both are admin-assigned, read-only for caregivers.

### Flutter (Both Apps)
- Do NOT import Flutter in `packages/vitacare_shared`. Pure Dart only.
- Do NOT put layout widgets, buttons, or text fields in `packages/vitacare_ui`.
- Do NOT use `ImageSource.gallery` for selfie capture. Camera only.
- Do NOT build a full ThemeData in the shared UI package.
- Do NOT queue offline writes. All mutations require internet.
- Show bottom navigation at all times after registration. Caregivers can browse jobs even before approval (motivates onboarding).
- Do NOT navigate to Advanced Details unless status is `call_verified` or `rejected` (rejected caregivers resubmit through the same screen, "Edit & Resubmit" from Profile View — prefilled from their previous submission).
- Do NOT allow caregivers to modify service_modes. Admin-assigned, read-only for caregivers.

### General
- Do NOT add features beyond V1 scope (no booking, payments, messaging, AI).
- Do NOT add dark mode, i18n, rate limiting, HTML emails in V1.
- Do NOT use code generation (build_runner, json_serializable) in shared packages.
- Do NOT commit .env files.

## Verification Status Transitions

Admin has an unrestricted override (`PATCH /admin/caregivers/:id/status` accepts any of the 8 statuses below as a target, from any current status — no transition-matrix check). The matrix below documents the *normal* flow — what caregiver actions, system triggers, and admin-web's quick-action buttons (Start Review/Approve/Reject) actually produce day to day:

```
pending_call → call_verified                     (admin: call-verified endpoint)
call_verified → pending_verification             (caregiver: submit advanced details)
pending_verification → in_process                (admin: status endpoint)
pending_verification → available                 (admin: approve — sets verified_at, green icon)
pending_verification → rejected                  (admin: status endpoint)
in_process → available                           (admin: approve — sets verified_at, green icon)
in_process → rejected                            (admin: status endpoint)
available → unavailable                          (caregiver OR admin: "not taking work right now")
unavailable → available                          (caregiver OR admin: "ready for work again")
available → assigned                             (admin: assign — ONLY from available, NOT unavailable)
assigned → available                             (admin: unassign — work completed)
available → pending_verification                 (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
unavailable → pending_verification               (admin: manual reset for re-review; OR system: caregiver changed phone / re-uploaded Aadhaar)
rejected → pending_verification                  (caregiver: re-submit)
```

**Notes:**
- `available` = verified + taking work. Green icon. Can respond to jobs.
- `unavailable` = verified but NOT taking work. Green icon (still verified) but greyed out. Cannot respond to jobs, cannot be assigned.
- `assigned` = currently working. Cannot toggle availability (admin must unassign first).
- Daily push at 8 AM reminds available/unavailable caregivers to confirm status. No response = no change.

## Enum Values (Source of Truth)

### Languages
hindi, english, kannada, tamil, telugu, malayalam, bengali, gujarati, marathi

### Service Modes
24hrs_live_in, 12hrs_pg

### Religion
hindu, muslim, christian, others

### Work Types (admin-assigned, caregiver read-only)
companion_care, bedside_care, critical_care

### Cities (preferred city for availability)
bangalore, mumbai, hyderabad, chennai, pune, delhi, gurgaon

### Qualifications
bsc_gnm_completed, anm_completed, bsc_gnm_anm_backlog, bsc_gnm_anm_student, non_nursing

### Gender
male, female, other

### User Roles
super_admin, admin, caregiver

### Job Status
active, closed

### Job Response
accepted, rejected, more_details

## File References

- Full requirements: `PRD.md`
- Technical spec: `SPEC.md`
- API contract: `docs/api-contract.yaml`
- Database ERD: `docs/database-erd.md`
- Test plan: `docs/test-plan.md`
- Environment setup: `docs/environment-setup.md`

## Sync Rule

Enums and validation constants exist in BOTH `packages/shared-constants` (TypeScript) and `packages/vitacare_shared` (Dart). When modifying an enum or constant, update BOTH packages in the same commit.
