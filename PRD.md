# VitaCare - Product Requirements Document (PRD)

**Version:** 1.0  
**Company:** VitaCasaHealth (VitaHealth)  
**Product:** VitaCare  
**Platform:** Flutter Mobile App (Android first, iOS using the same codebase)  
**Admin Portal:** Flutter Web App (separate from mobile)  
**Family/Patient App:** Separate Flutter Mobile App (shares same backend & database)  
**Backend:** NestJS + Supabase PostgreSQL  
**Target Team:** 1-2 developers  
**Target Timeline:** 6-8 weeks  

---

## 1. Objective

Build a mobile application that enables caregivers to register on the VitaCare platform and allows administrators to verify, approve, and manage caregiver profiles through a dedicated web dashboard.

Caregivers provide in-home care services for elderly patients, post-operative patients, and individuals needing daily living assistance (bathing, diaper changes, mobility support, medication reminders, etc.).

Version 1 focuses only on caregiver onboarding and verification.

---

## 2. Goals

- Simple caregiver onboarding (phone-first, no OTP).
- Two-stage verification (office call + admin document review).
- Secure document submission (Aadhaar, qualification docs).
- Admin verification workflow.
- Email notifications.
- Audit trail.
- Scalable architecture for future healthcare services.

---

## 3. User Roles

### Super Admin

Can:
- Login.
- Create Admin accounts.
- Manage Admins.
- Manage Caregivers.
- Verify profiles.
- Reset passwords.
- View audit logs.

**Provisioning:** First Super Admin is seeded via database migration/seed script.

### Admin

Can:
- Login.
- View caregivers.
- Search and filter.
- Review documents.
- Make office verification calls.
- Add notes.
- Update verification status.
- Edit caregiver profiles.
- Reset caregiver passwords.
- View audit logs.

Cannot create other admins.

### Caregiver

Can:
- Register (phone + basic info + selfie).
- Login.
- Fill advanced details (after office call).
- Upload documents.
- Update availability.
- View verification status.
- View rejection reason (if provided by admin).

Cannot verify profiles.

---

## 4. Technology Stack

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter + Dart |
| Admin Web Dashboard | Flutter Web + Dart |
| Backend API | NestJS + TypeScript |
| Database | Supabase PostgreSQL |
| Authentication | Custom JWT (bcrypt + jsonwebtoken, no Supabase Auth) |
| Authorization | NestJS Role-Based Guards |
| File Storage | Supabase Storage |
| Email | Nodemailer + Gmail SMTP (plain text for V1) |
| Push Notifications | Firebase Cloud Messaging (FCM) |

---

## 5. System Architecture

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Flutter Mobile   │  │  Flutter Mobile   │  │  Flutter Web      │
│  (Caregiver App)  │  │  (Family App V2)  │  │  (Admin Dashboard)│
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                │ HTTPS
                                ▼
         ┌───────────────────────┐
         │   NestJS API Server   │
         │   (Shared Backend)    │
         ├───────────────────────┤
         │  - Auth Guards        │
         │  - Role-Based Access  │
         │  - Validation Pipes   │
         │  - Audit Interceptor  │
         └───────────┬───────────┘
                     │
      ┌──────────────┼──────────────┐
      │              │              │
      ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│ Supabase │  │ Supabase │  │ Gmail SMTP   │
│ Postgres │  │ Storage  │  │ (Nodemailer) │
└──────────┘  └──────────┘  └──────────────┘
```

---

## 6. Authentication

### Login Method

Caregivers register and log in using:
- **Phone Number** — no OTP verification during initial registration. Phone is verified via office call.

After advanced details are filled, caregivers can also use email + password for login.

### Admin Login

Admins log in via email + password only.

### Session Management

- Custom JWT tokens issued by NestJS backend.
- Access tokens validated in NestJS guards.
- Refresh tokens stored server-side, rotated on each use.

---

## 7. Registration & Onboarding Flow

### Stage 1: Initial Registration (Simple)

Caregiver provides:
- First Name (required)
- Last Name (required)
- Phone Number (required, unique, with country code)
- Gender (required: Male / Female / Other)
- Age (required, 18-65)
- Languages Spoken (required, multi-select, at least one)
- Selfie Photo (required, camera capture)

**No OTP verification.** No password at this stage.

**Validation:**
- Phone number format validation (Indian mobile: +91XXXXXXXXXX).
- Duplicate phone check before submission.
- Selfie must be a live camera capture (not gallery).

**After submission:**
- Profile status set to "Pending Call".
- Caregiver sees message: "Thank you for registering. You will receive a call from our office shortly."
- Admin is notified of new registration.

### Stage 2: Office Call Verification

- Admin/office staff calls the caregiver to verify phone number is valid.
- During the call, caregiver is asked to fill advanced details in the app.
- Admin marks profile as "Call Verified" in the dashboard.
- Caregiver is now able to access the advanced details form in the app.

### Stage 3: Advanced Details

After call verification, caregiver fills:
- Highest Qualification (see Section 9)
- Qualification Document (upload, PDF/JPG/PNG, max 10MB)
- Aadhaar Card (upload, PDF/JPG/PNG, max 10MB)
- Current Address (text)
- Email ID (optional but recommended)
- Password (min 6 characters, for future email-based login)
- Areas of Expertise (multi-select, at least one, see Section 10)
- Service Modes (multi-select, at least one: Live-in / 24hr PG / 12hr PG)
- Any Other Documents (optional, up to 3 files, max 10MB each)

### Stage 4: Admin Document Verification

- Admin reviews uploaded documents (Aadhaar, qualification, other docs).
- Admin verifies or rejects the caregiver.
- If rejected, optional reason is provided.

### Stage 5: Availability Setup (Post-Verification)

- After verification, caregiver sets availability (hours, dates, service mode).
- Caregiver becomes active and visible for future matching.

---

## 8. Profile Information

### Basic Profile (Stage 1)

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| First Name | String | Yes | Max 100 characters |
| Last Name | String | Yes | Max 100 characters |
| Phone Number | String | Yes | Unique, +91XXXXXXXXXX format |
| Gender | Enum | Yes | Male / Female / Other |
| Age | Integer | Yes | 18-65 |
| Languages Spoken | Multi-select | Yes | Min 1, see Section 11 |
| Selfie Photo | Image | Yes | Camera capture only, max 5MB, JPG/PNG |

### Advanced Profile (Stage 3)

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| Highest Qualification | Enum | Yes | See Section 9 |
| Qualification Document | File | Yes | PDF/JPG/PNG, max 10MB |
| Aadhaar Card | File | Yes | PDF/JPG/PNG, max 10MB |
| Current Address | Text | Yes | Max 500 characters |
| Email ID | String | No | Valid email format |
| Password | String | Yes | Min 6 characters |
| Other Documents | Files | No | Up to 3 files, max 10MB each |
| Areas of Expertise | Multi-select | Yes | Min 1, see Section 10 |
| Terms & Conditions | Boolean | Yes | Must accept |

---

## 9. Highest Qualification Options

- GNM (General Nursing and Midwifery)
- ANM (Auxiliary Nurse Midwife)
- BSc Nursing
- MSc Nursing
- Diploma in Home Health Aide
- Diploma in Geriatric Care
- 10th Pass
- 12th Pass
- Other (specify)

---

## 10. Expertise Areas

Multi-select. At least one required.

- Elder Care
- Post-Operative Care
- Bathing & Hygiene
- Diaper Change
- Mobility Assistance
- Feeding Assistance
- Medication Reminders
- Wound Dressing (Basic)
- Physiotherapy Support
- Bedsore Prevention
- Catheter Care
- Vital Signs Monitoring (BP, Temperature, Sugar)
- Companionship
- Night Care
- Dementia / Alzheimer's Care
- Palliative Care
- Stroke Recovery Support

---

## 11. Languages

Multi-select. At least one required.

- English
- Hindi
- Kannada
- Tamil
- Telugu
- Malayalam
- Gujarati
- Marathi
- Bengali

---

## 12. Verification Workflow

### Status Values

| Status | Description |
|--------|-------------|
| Pending Call | Registered, awaiting office call |
| Call Verified | Office call completed, advanced details unlocked |
| Pending Verification | Advanced details submitted, awaiting admin document review |
| In Process | Admin has started reviewing documents |
| Verified | Approved and active |
| Rejected | Not approved (can re-submit) |

**Default:** Pending Call.

### Admin Actions

- View new registrations (Pending Call).
- Mark as "Call Verified" after successful phone call.
- Review advanced details and documents.
- Add internal notes.
- Approve → status becomes "Verified".
- Reject → status becomes "Rejected", optional message to caregiver.
- Move to "In Process" → signals review has started.

### Re-submission After Rejection

- Caregiver can edit ALL details (basic profile, advanced details, and re-upload documents).
- No new office call is required.
- Status returns to "Pending Verification" upon re-submission.
- Full audit trail is maintained.

---

## 13. Admin Notes

Admins can maintain per-caregiver:
- Internal Notes (free text)
- Hourly Rate (numeric)
- Preferred Service Mode (Live-in / 24hr PG / 12hr PG)
- Availability Remarks (free text)

**Visibility:** Admin and Super Admin only. Never exposed to caregivers.

---

## 14. Service Modes

Caregivers can indicate their preferred service modes:

| Mode | Description |
|------|-------------|
| Live-in | Caregiver lives at the patient's home |
| 24hr (PG) | Works 24-hour shifts but lives in a nearby PG |
| 12hr (PG) | Works 12-hour shifts and lives in a nearby PG |

Caregivers can select one or more modes they are willing to work in.

---

## 15. Availability Management

Caregivers can set:
- Available Service Modes (multi-select: Live-in, 24hr PG, 12hr PG)
- Available Days (multi-select: Mon-Sun)
- Start Date (when they can start a new assignment)
- Preferred Areas/Localities (free text or multi-select, city-specific)

**Rules:**
- Availability is set after verification.
- Updating availability does NOT change verification status.
- Updating availability sends notification to admins.

---

## 16. Profile Update Rules

When caregivers modify profile details (excluding availability):
- Save audit history (before/after values).
- Notify admins via email with changed fields.
- Profile is flagged as having pending edits for admin review.
- **Verification status does NOT change automatically.** Admin reviews edits and manually decides whether to reset status.
- Caregiver continues to operate at their current verification level while edits are under review.

**Exception:** Availability updates do not trigger any review flag.

### Account Recovery

If a caregiver loses access to their phone number:
- Caregiver calls the office.
- Admin verifies identity verbally.
- Admin changes the phone number from the admin dashboard.
- Caregiver can then login with the new number.

---

## 17. Email Notifications

**Provider:** Nodemailer + Gmail SMTP (plain text for V1).  
**Default admin notification email:** vitacasahealthindia@gmail.com

| Event | Recipients | Content |
|-------|-----------|---------|
| New Registration | Admin | New caregiver registered, pending call |
| Call Verified | Caregiver | Your phone has been verified, please fill advanced details |
| Advanced Details Submitted | Admin | New profile pending document review |
| Verified | Caregiver | Congratulations, profile approved |
| Rejected | Caregiver | Status update + optional reason |
| Profile Updated | Admin | Before/after values of changed fields |
| Availability Updated | Admin | New availability details |
| Password Reset | Caregiver | Reset link |

---

## 18. Admin Dashboard (Web)

### Overview Cards

- Total caregivers
- Pending Call
- Call Verified (awaiting advanced details)
- Pending Verification
- In Process
- Verified
- Rejected
- New registrations (last 24 hours)
- New registrations (last 7 days)

### Caregiver List

Sortable table with columns: Name, Phone, Gender, Age, Qualification, Service Mode, Status, Registration Date.

### Filters

- Name (text search)
- Phone (text search)
- Email (text search)
- Qualification (dropdown)
- Expertise (multi-select dropdown)
- Language (multi-select dropdown)
- Service Mode (dropdown)
- Verification Status (dropdown)
- Registration Date (date range picker)

### Time-based Quick Filters

- Last 24 hours
- Last 7 days
- Last 30 days
- Custom date range

### Caregiver Detail View

- Full profile information.
- Selfie viewer.
- Document viewer (inline PDF/image preview for Aadhaar, qualification, other docs).
- Verification status controls.
- Admin notes section.
- Audit history for this caregiver.

---

## 19. Audit Log

### Tracked Events

- Registration
- Login
- Call verification
- Advanced details submission
- Profile updates
- Verification status changes
- Password resets
- Availability changes
- Admin edits to caregiver profiles
- Admin note additions

### Record Structure

| Field | Description |
|-------|-------------|
| id | UUID |
| user_id | Who performed the action |
| target_user_id | Who was affected (if different) |
| action | Event type (enum) |
| entity_type | Table/resource affected |
| entity_id | ID of affected record |
| before_value | JSON snapshot before change |
| after_value | JSON snapshot after change |
| ip_address | Request origin |
| timestamp | UTC timestamp |

### Access

Viewable by both Admin and Super Admin roles.

---

## 20. Database Schema

### users

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE,
  phone VARCHAR(20) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('super_admin', 'admin', 'caregiver')),
  is_active BOOLEAN DEFAULT true,
  fcm_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### caregiver_profiles

```sql
CREATE TABLE caregiver_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  selfie_photo_url TEXT,
  gender VARCHAR(30) NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  age INTEGER NOT NULL CHECK (age >= 18 AND age <= 65),
  highest_qualification VARCHAR(100),
  qualification_document_url TEXT,
  aadhaar_document_url TEXT,
  current_address TEXT CHECK (char_length(current_address) <= 500),
  other_document_urls JSONB DEFAULT '[]',
  terms_accepted BOOLEAN DEFAULT false,
  verification_status VARCHAR(30) DEFAULT 'pending_call'
    CHECK (verification_status IN ('pending_call', 'call_verified', 'pending_verification', 'in_process', 'verified', 'rejected')),
  rejection_message TEXT,
  call_verified_at TIMESTAMPTZ,
  call_verified_by UUID REFERENCES users(id),
  advanced_details_completed BOOLEAN DEFAULT false,
  has_pending_edits BOOLEAN DEFAULT false,
  submitted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### caregiver_languages

```sql
CREATE TABLE caregiver_languages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  language VARCHAR(50) NOT NULL,
  UNIQUE(profile_id, language)
);
```

### caregiver_expertise

```sql
CREATE TABLE caregiver_expertise (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  expertise VARCHAR(100) NOT NULL,
  UNIQUE(profile_id, expertise)
);
```

### caregiver_service_modes

```sql
CREATE TABLE caregiver_service_modes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  service_mode VARCHAR(20) NOT NULL CHECK (service_mode IN ('live_in', '24hr_pg', '12hr_pg')),
  UNIQUE(profile_id, service_mode)
);
```

### caregiver_availability

```sql
CREATE TABLE caregiver_availability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID UNIQUE NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  preferred_localities TEXT CHECK (char_length(preferred_localities) <= 500),
  notes TEXT CHECK (char_length(notes) <= 500),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### admin_notes

```sql
CREATE TABLE admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES users(id),
  internal_notes TEXT,
  rate_live_in DECIMAL(10, 2),
  rate_24hr_pg DECIMAL(10, 2),
  rate_12hr_pg DECIMAL(10, 2),
  availability_remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id)
);
```

### audit_logs

```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  target_user_id UUID REFERENCES users(id),
  action VARCHAR(50) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID,
  before_value JSONB,
  after_value JSONB,
  ip_address INET,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_target_user_id ON audit_logs(target_user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
```

---

## 21. API Endpoints

### Authentication

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/auth/register` | Register caregiver (phone + basic info) | Public |
| POST | `/auth/login/phone` | Login with phone number | Public |
| POST | `/auth/login/email` | Login with email + password (after advanced details) | Public |
| POST | `/auth/forgot-password` | Request password reset email | Public |
| POST | `/auth/reset-password` | Reset password with token | Public |
| POST | `/auth/refresh` | Refresh access token | Authenticated |
| POST | `/auth/logout` | Invalidate session | Authenticated |

### Caregiver Profile

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/caregiver/profile` | Get own profile | Caregiver |
| PUT | `/caregiver/profile/basic` | Update basic profile | Caregiver |
| PUT | `/caregiver/profile/advanced` | Submit advanced details | Caregiver |
| POST | `/caregiver/profile/selfie` | Upload selfie photo | Caregiver |
| POST | `/caregiver/profile/documents` | Upload documents (qualification, Aadhaar, other) | Caregiver |
| GET | `/caregiver/verification-status` | Get current verification status | Caregiver |

### Caregiver Availability

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/caregiver/jobs` | Get active job listings | Caregiver |
| POST | `/caregiver/jobs/:id/respond` | Respond to a job (accept/reject/more details) | Caregiver |

### Admin - Caregiver Management

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/admin/caregivers` | List caregivers (paginated, filterable) | Admin |
| GET | `/admin/caregivers/:id` | Get caregiver detail | Admin |
| PUT | `/admin/caregivers/:id` | Edit caregiver profile | Admin |
| PATCH | `/admin/caregivers/:id/status` | Update verification status | Admin |
| PATCH | `/admin/caregivers/:id/call-verified` | Mark as call verified | Admin |
| POST | `/admin/caregivers/:id/notes` | Add/update admin notes | Admin |
| GET | `/admin/caregivers/:id/documents` | Get document URLs | Admin |
| POST | `/admin/caregivers/:id/reset-password` | Reset caregiver password | Admin |

### Admin - Dashboard

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/admin/dashboard/stats` | Get dashboard statistics | Admin |

### Super Admin - Admin Management

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/admin/users` | Create admin account | Super Admin |
| GET | `/admin/users` | List admin accounts | Super Admin |
| PUT | `/admin/users/:id` | Update admin account | Super Admin |
| DELETE | `/admin/users/:id` | Deactivate admin account | Super Admin |

### Audit Logs

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/admin/audit-logs` | List audit logs (paginated, filterable) | Admin |
| GET | `/admin/audit-logs/:userId` | Get logs for specific user | Admin |

### Common Query Parameters (List Endpoints)

- `page` — Page number (default: 1)
- `limit` — Items per page (default: 20, max: 100)
- `sort` — Sort field (e.g., `created_at`)
- `order` — Sort direction (`asc` / `desc`)
- `search` — Text search (name, phone)
- `status` — Filter by verification status
- `qualification` — Filter by qualification
- `expertise` — Filter by expertise area
- `language` — Filter by language
- `service_mode` — Filter by service mode
- `from_date` — Registration date from
- `to_date` — Registration date to

---

## 22. Security

- Custom JWT authentication (bcrypt + jsonwebtoken).
- JWT validation in NestJS guards.
- Role-based authorization on all endpoints.
- Secure document storage with signed URLs (time-limited access).
- HTTPS only (enforced at infrastructure level).
- Passwords hashed with bcrypt (10 salt rounds), stored in application database.
- File upload validation: size limits (10MB max).
- Input sanitization on all user-provided fields.
- Aadhaar data handled with care (no plain text storage of Aadhaar number in DB).
- Refresh tokens hashed and rotated on each use.

---

## 23. Non-Functional Requirements

- Mobile-first experience for caregivers.
- Responsive admin web dashboard.
- Profile loading < 2 seconds.
- File upload with progress indicator.
- Scalable architecture (stateless API, managed database).
- Clean modular code (NestJS modules per domain).
- Comprehensive error handling with user-friendly messages.
- Activity logging via audit interceptor.
- API response format: `{ success: boolean, data?: T, error?: { code: string, message: string } }`.

---

## 24. Error Handling

### Client-Side (Flutter)

- Network errors: retry with exponential backoff, show offline banner.
- Validation errors: inline field-level error messages.
- Upload failures: resume/retry capability.
- Session expiry: auto-refresh token, redirect to login if refresh fails.

### Server-Side (NestJS)

- Consistent error response format across all endpoints.
- Validation pipe for request body/params.
- Global exception filter for unhandled errors.
- Never expose stack traces or internal details in production.

---

## 25. Product Roadmap Overview

| Version | Focus | Timeline |
|---------|-------|----------|
| V1 | Caregiver onboarding & admin verification | 6-8 weeks |
| V2 | Family/patient registration, discovery, booking & assignments | 8-10 weeks |
| V3 | Reviews, analytics, platform polish | 4-6 weeks |
| V4+ | AI matching, scale & advanced features | Ongoing |

---

## 26. Version 1 — Caregiver Onboarding & Verification

### Scope

- Authentication (phone-based registration, email+password after advanced details).
- Caregiver registration & two-stage onboarding.
- Document upload (selfie, Aadhaar, qualification docs, other docs).
- Profile management.
- Admin web portal (Flutter Web).
- Two-stage verification workflow (office call + document review).
- Availability management.
- Service mode selection.
- Email notifications (plain text via Nodemailer + Gmail SMTP).
- Audit logs.
- Super Admin seed script.

### V1 Development Milestones

#### Phase 1: Foundation (Weeks 1-2)

- [ ] Project setup (Flutter app, Flutter web, NestJS API).
- [ ] Supabase project configuration (database, storage, realtime).
- [ ] Database schema creation and migrations.
- [ ] Super Admin seed script.
- [ ] Authentication module (register with phone, login, JWT guards).
- [ ] Role-based authorization guards.
- [ ] Basic CI pipeline.

#### Phase 2: Caregiver Onboarding (Weeks 3-4)

- [ ] Registration flow - Stage 1 (phone + name + gender + age + languages + selfie).
- [ ] "Pending Call" status screen with message.
- [ ] Advanced details form (unlocked after call verification).
- [ ] File upload (selfie, qualification doc, Aadhaar, other docs).
- [ ] Profile submission flow.
- [ ] Caregiver profile API endpoints.
- [ ] Service mode selection.

#### Phase 3: Admin Dashboard (Weeks 4-5)

- [ ] Admin web app setup.
- [ ] Dashboard overview (stats cards).
- [ ] Caregiver list with search/filter.
- [ ] Caregiver detail view with document viewer.
- [ ] Call verification action (mark as call verified).
- [ ] Document verification status management.
- [ ] Admin notes CRUD.
- [ ] Super Admin → Admin account management.

#### Phase 4: Notifications & Audit (Weeks 5-6)

- [ ] Email notification service (Nodemailer + Gmail SMTP integration).
- [ ] Registration notification emails.
- [ ] Call verified notification to caregiver.
- [ ] Verification status change emails.
- [ ] Profile update notification emails.
- [ ] Audit log interceptor.
- [ ] Audit log viewer in admin dashboard.

#### Phase 5: Availability & Polish (Weeks 7-8)

- [ ] Availability management (API + UI).
- [ ] End-to-end testing.
- [ ] Error handling review.
- [ ] UI polish and edge case fixes.
- [ ] Profile update → re-verification flow testing.
- [ ] Re-submission after rejection flow testing.
- [ ] Android build and Play Store prep.
- [ ] Admin web deployment.
- [ ] API deployment.
- [ ] Production Supabase setup.

### V1 Success Criteria

- Caregivers can register with phone + basic info + selfie.
- Admin can mark caregivers as call-verified.
- Call-verified caregivers can fill advanced details and upload documents.
- Admins can verify or reject profiles via the web dashboard.
- Rejected caregivers can re-submit after editing.
- Email notifications are delivered correctly for all defined events.
- Audit logs capture all critical actions with before/after values.
- Verified caregivers can set their availability and service modes.
- Admin dashboard displays accurate statistics and supports filtering.
- The mobile app is deployable on Android with future iOS support.
- The admin web dashboard is deployed and accessible.

---

## 27. Version 2 — Family/Patient Side, Discovery & Assignments

> **Note:** The family/patient side is a **separate Flutter mobile app** but shares the same NestJS backend and Supabase database as the caregiver app.

### 27.1 New User Role: Family/Patient

Can:
- Register (phone or email).
- Login.
- Browse and search caregivers.
- Request a caregiver (specify service mode, duration, patient details).
- View assigned caregiver profile.
- Rate caregiver after assignment ends.
- Message caregivers (via admin-mediated or direct).

### 27.2 Family/Patient Registration & Profile

| Field | Type | Required |
|-------|------|----------|
| Name (Contact Person) | String | Yes |
| Phone | String | Yes |
| Email | String | No |
| Patient Name | String | Yes |
| Patient Age | Integer | Yes |
| Patient Gender | Enum | Yes |
| Patient Condition | Text (max 500 chars) | Yes |
| Service Mode Required | Enum | Yes (Live-in / 24hr PG / 12hr PG) |
| Address | Text | Yes |
| City/Locality | String | Yes |

### 27.3 Caregiver Discovery

#### Browse & Filter

Families can browse verified caregivers with filters:
- Expertise area
- Language
- Gender preference
- Service mode
- Availability
- Locality/Area

Sort options: Newest, Name (A-Z), Experience.

### 27.4 Assignment Flow

- Family requests a caregiver (or admin matches manually).
- Admin confirms assignment.
- Both parties are notified.
- Assignment has start date and expected duration.
- Either party can end the assignment (with notice).

### 27.5 V2 Development Milestones

#### Phase 1: Family Foundation (Weeks 1-2)

- [ ] Family/patient registration & authentication.
- [ ] Family profile creation with patient details.
- [ ] Caregiver public profile (read-only view for families).
- [ ] Browse/search caregivers with filters.

#### Phase 2: Assignment System (Weeks 3-5)

- [ ] Caregiver request flow (family → admin → caregiver).
- [ ] Assignment management (start, end, extend).
- [ ] Admin matching interface.
- [ ] Notifications for all assignment events.

#### Phase 3: Communication & Polish (Weeks 6-8)

- [ ] In-app messaging between family and caregiver.
- [ ] Assignment history.
- [ ] End-to-end testing.
- [ ] iOS build preparation.

---

## 28. User Flows

### Caregiver Registration Flow (V1)

```
Start → Enter Phone + Name + Gender + Age + Languages → Capture Selfie → Submit
  → Status: Pending Call → See "You will receive a call" message
  → [Office calls, verifies phone] → Status: Call Verified
  → Fill Advanced Details (Qualification, Docs, Aadhaar, Address, Email, Password)
  → Submit Advanced Details → Status: Pending Verification
  → [Admin reviews documents]
  → [Verified] → Set Availability + Service Modes → Full Access
  → [Rejected] → View Reason → Edit & Re-submit → Back to Pending Verification
```

### Admin Verification Flow (V1)

```
Dashboard → See Pending Call Count → Open Caregiver List (filter: Pending Call)
  → Call Caregiver → Mark as "Call Verified"
  → [Caregiver fills advanced details]
  → See Pending Verification Count → Open Detail View
  → Review Documents (Aadhaar, Qualification, Other)
  → [Approve] → Status: Verified → Email sent to Caregiver
  → [Reject] → Optional Reason → Status: Rejected → Email sent to Caregiver
```

### Profile Update Flow (V1)

```
Caregiver edits profile → Save changes
  → Audit log records before/after
  → Profile flagged as "has pending edits"
  → Email sent to Admin with changes
  → Caregiver continues with current status (no interruption)
  → Admin reviews edits → [Approve: no action needed] or [Reset status manually if needed]
```

### Availability Update Flow (V1 — no re-verification)

```
Caregiver updates availability/service modes → Save
  → Audit log records change
  → Email sent to Admin
  → Status remains unchanged
```

---

## 29. Overall Success Metrics

| Metric | Target (6 months post-V2 launch) |
|--------|----------------------------------|
| Registered caregivers | 100+ verified |
| Registered families | 200+ |
| Active assignments per month | 50+ |
| Average caregiver rating | 4.0+ |
| Assignment completion rate | > 85% |
| Family retention (repeat assignment) | > 40% |
| App crash rate | < 1% |
| API response time (p95) | < 500ms |
