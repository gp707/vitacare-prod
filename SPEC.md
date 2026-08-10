# VitaCare — Technical Specification (V1)

**Version:** 1.0  
**Scope:** Caregiver Onboarding & Admin Verification  
**Last Updated:** 2026-08-01  

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Structure](#2-repository-structure)
3. [Authentication & Authorization](#3-authentication--authorization)
4. [Database Schema](#4-database-schema)
5. [File Storage](#5-file-storage)
6. [API Specification](#6-api-specification)
7. [Error Catalog](#7-error-catalog)
8. [Push Notifications](#8-push-notifications)
9. [Real-Time Updates](#9-real-time-updates)
10. [Email Notifications](#10-email-notifications)
11. [Audit Logging](#11-audit-logging)
12. [Mobile App — Screens & Navigation](#12-mobile-app--screens--navigation)
13. [Admin Dashboard — Screens & Navigation](#13-admin-dashboard--screens--navigation)
14. [Offline Support](#14-offline-support)
15. [Constraints & Explicit Rules](#15-constraints--explicit-rules)

---

## 1. Architecture Overview

```
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  Caregiver App        │  │  Family App (V2)      │  │  Admin Dashboard     │
│  Flutter Mobile       │  │  Flutter Mobile       │  │  Flutter Web         │
│  apps/caregiver-app   │  │  apps/family-app      │  │  apps/admin-web      │
└──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
           │                          │                          │
           └──────────────────────────┼──────────────────────────┘
                                      │ HTTPS (REST)
                                      ▼
                       ┌───────────────────────────┐
                       │   NestJS API Server        │
                       │   apps/api                 │
                       ├───────────────────────────┤
                       │  - JWT Auth Guards         │
                       │  - Role-Based Guards       │
                       │  - Validation Pipes        │
                       │  - Audit Interceptor       │
                       │  - Global Exception Filter │
                       └───────────────┬───────────┘
                                       │
            ┌──────────────────────────┼──────────────┐
            │                          │              │
            ▼                          ▼              ▼
     ┌──────────────┐          ┌──────────┐    ┌────────────────┐
     │ Supabase     │          │ Supabase │    │  Gmail SMTP    │
     │ PostgreSQL   │          │ Storage  │    │  (Nodemailer)  │
     │ + Realtime   │          └──────────┘    └────────────────┘
     └──────────────┘
```

### Technology Choices

| Component | Technology | Version (minimum) |
|-----------|-----------|-------------------|
| Mobile App | Flutter | 3.19+ |
| Admin Web | Flutter Web | 3.19+ |
| State Management | Riverpod | 2.x |
| Backend | NestJS | 10.x |
| Runtime | Node.js | 20 LTS |
| Database | PostgreSQL (Supabase) | 15+ |
| Auth | Custom JWT (bcrypt + jsonwebtoken) | Latest |
| Storage | Supabase Storage | Latest |
| Real-time | Supabase Realtime | Latest |
| Email | Nodemailer + Gmail SMTP | Latest |
| Push | Firebase Cloud Messaging | Latest |
| HTTP Client (Flutter) | Dio | 5.x |
| Local Storage (Flutter) | Hive or SharedPreferences | Latest |

---

## 2. Repository Structure

**Single monorepo** containing all apps and shared packages.

```
vitacare/
├── apps/
│   ├── api/                          # NestJS Backend
│   │   ├── src/
│   │   │   ├── main.ts
│   │   │   ├── app.module.ts
│   │   │   ├── common/
│   │   │   │   ├── guards/
│   │   │   │   │   ├── jwt-auth.guard.ts
│   │   │   │   │   └── roles.guard.ts
│   │   │   │   ├── decorators/
│   │   │   │   │   ├── roles.decorator.ts
│   │   │   │   │   └── current-user.decorator.ts
│   │   │   │   ├── interceptors/
│   │   │   │   │   └── audit.interceptor.ts
│   │   │   │   ├── filters/
│   │   │   │   │   └── global-exception.filter.ts
│   │   │   │   ├── pipes/
│   │   │   │   │   └── validation.pipe.ts
│   │   │   │   └── dto/
│   │   │   │       └── pagination.dto.ts
│   │   │   ├── auth/
│   │   │   │   ├── auth.module.ts
│   │   │   │   ├── auth.controller.ts
│   │   │   │   ├── auth.service.ts
│   │   │   │   └── dto/
│   │   │   ├── caregiver/
│   │   │   │   ├── caregiver.module.ts
│   │   │   │   ├── caregiver.controller.ts
│   │   │   │   ├── caregiver.service.ts
│   │   │   │   └── dto/
│   │   │   ├── admin/
│   │   │   │   ├── admin.module.ts
│   │   │   │   ├── admin.controller.ts
│   │   │   │   ├── admin.service.ts
│   │   │   │   └── dto/
│   │   │   ├── notification/
│   │   │   │   ├── notification.module.ts
│   │   │   │   ├── email.service.ts
│   │   │   │   └── push.service.ts
│   │   │   ├── audit/
│   │   │   │   ├── audit.module.ts
│   │   │   │   └── audit.service.ts
│   │   │   └── upload/
│   │   │       ├── upload.module.ts
│   │   │       ├── upload.controller.ts
│   │   │       └── upload.service.ts
│   │   ├── test/
│   │   ├── .env.example
│   │   ├── nest-cli.json
│   │   ├── tsconfig.json
│   │   └── package.json
│   │
│   ├── caregiver-app/                # Flutter Mobile (Caregiver)
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── app/
│   │   │   │   ├── app.dart
│   │   │   │   └── router.dart
│   │   │   ├── core/
│   │   │   │   ├── network/
│   │   │   │   │   ├── api_client.dart
│   │   │   │   │   └── api_interceptors.dart
│   │   │   │   ├── storage/
│   │   │   │   │   └── local_storage.dart
│   │   │   │   └── errors/
│   │   │   ├── features/
│   │   │   │   ├── auth/
│   │   │   │   ├── registration/
│   │   │   │   ├── profile/
│   │   │   │   ├── availability/
│   │   │   │   └── notifications/
│   │   │   └── shared/
│   │   │       └── widgets/          # App-specific widgets only
│   │   ├── android/
│   │   ├── ios/
│   │   ├── assets/
│   │   ├── pubspec.yaml
│   │   └── analysis_options.yaml
│   │
│   └── admin-web/                    # Flutter Web (Admin Dashboard)
│       ├── lib/
│       │   ├── main.dart
│       │   ├── app/
│       │   │   ├── app.dart
│       │   │   └── router.dart
│       │   ├── core/
│       │   │   ├── network/
│       │   │   └── realtime/
│       │   │       └── supabase_realtime.dart
│       │   ├── features/
│       │   │   ├── auth/
│       │   │   ├── dashboard/
│       │   │   ├── caregivers/
│       │   │   ├── admin_management/
│       │   │   └── audit_logs/
│       │   └── shared/
│       │       └── widgets/          # App-specific widgets only
│       ├── web/
│       ├── pubspec.yaml
│       └── analysis_options.yaml
│
├── packages/
│   ├── shared-constants/             # TypeScript shared constants (used by API)
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   ├── enums.ts             # All enum values
│   │   │   ├── error-codes.ts       # Error code definitions
│   │   │   ├── validation.ts        # Validation rules (regex, limits)
│   │   │   └── config.ts            # Shared config constants
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   ├── vitacare_shared/              # Dart shared package (used by both Flutter apps)
│   │   ├── lib/
│   │   │   ├── vitacare_shared.dart  # Barrel export
│   │   │   ├── constants/
│   │   │   │   ├── enums.dart        # All enum values (mirrors TS enums)
│   │   │   │   ├── error_codes.dart  # Error code constants
│   │   │   │   ├── validation.dart   # Validation rules
│   │   │   │   └── api_routes.dart   # API endpoint path constants
│   │   │   ├── models/
│   │   │   │   ├── user_model.dart
│   │   │   │   ├── caregiver_profile_model.dart
│   │   │   │   ├── availability_model.dart
│   │   │   │   ├── admin_note_model.dart
│   │   │   │   ├── audit_log_model.dart
│   │   │   │   └── api_response_model.dart
│   │   │   └── utils/
│   │   │       ├── validators.dart   # Shared validation functions
│   │   │       └── formatters.dart   # Phone, date formatting
│   │   ├── pubspec.yaml
│   │   └── analysis_options.yaml
│   │
│   └── vitacare_ui/                  # Dart shared UI package (design tokens + micro-widgets)
│       ├── lib/
│       │   ├── vitacare_ui.dart      # Barrel export
│       │   ├── theme/
│       │   │   ├── app_colors.dart   # Color palette
│       │   │   ├── app_typography.dart # Font family, weight scale (NOT sizes)
│       │   │   └── app_spacing.dart  # Base spacing unit (4px grid)
│       │   └── widgets/
│       │       ├── vita_status_badge.dart
│       │       ├── vita_multi_select_chips.dart
│       │       ├── vita_loading_indicator.dart
│       │       └── vita_offline_banner.dart
│       ├── pubspec.yaml
│       └── analysis_options.yaml
│
├── supabase/
│   ├── migrations/
│   │   ├── 001_create_users.sql
│   │   ├── 002_create_refresh_tokens.sql
│   │   ├── 003_create_caregiver_profiles.sql
│   │   ├── 004_create_caregiver_languages.sql
│   │   ├── 005_create_caregiver_service_modes.sql
│   │   ├── 006_create_caregiver_work_types.sql
│   │   ├── 007_create_admin_notes.sql
│   │   ├── 008_create_jobs.sql
│   │   ├── 009_create_job_responses.sql
│   │   └── 010_create_audit_logs.sql
│   ├── seed.sql
│   └── config.toml
│
├── .gitignore
├── README.md
├── PRD.md
├── SPEC.md
└── melos.yaml                        # Monorepo workspace manager for Dart/Flutter
```

### 2.1 Workspace Tooling

#### Dart/Flutter — Melos

[Melos](https://melos.invertase.dev/) manages the Flutter/Dart packages in the monorepo.

**`melos.yaml`** (root):
```yaml
name: vitacare
packages:
  - apps/caregiver-app
  - apps/admin-web
  - packages/vitacare_shared
  - packages/vitacare_ui

scripts:
  analyze:
    run: melos exec -- flutter analyze
  test:
    run: melos exec -- flutter test
  get:
    run: melos exec -- flutter pub get
```

#### TypeScript/NestJS — npm workspace

The API and shared-constants use npm workspaces.

**Root `package.json`** (only for TypeScript workspace):
```json
{
  "name": "vitacare-ts",
  "private": true,
  "workspaces": [
    "apps/api",
    "packages/shared-constants"
  ]
}
```

The API imports shared constants like:
```typescript
import { ErrorCodes, Enums, Validation } from '@vitacare/shared-constants';
```

#### Flutter apps reference shared packages via path:

**`apps/caregiver-app/pubspec.yaml`:**
```yaml
dependencies:
  vitacare_shared:
    path: ../../packages/vitacare_shared
  vitacare_ui:
    path: ../../packages/vitacare_ui
```

**`apps/admin-web/pubspec.yaml`:**
```yaml
dependencies:
  vitacare_shared:
    path: ../../packages/vitacare_shared
  vitacare_ui:
    path: ../../packages/vitacare_ui
```

### 2.2 Shared Constants — Single Source of Truth

Enums and validation rules are defined in both `packages/shared-constants` (TypeScript) and `packages/vitacare_shared` (Dart). These MUST be kept in sync manually.

**Sync rule:** When adding/modifying an enum or validation constant, update BOTH packages in the same commit.

#### `packages/shared-constants/src/enums.ts`:
```typescript
export const VerificationStatus = {
  PENDING_CALL: 'pending_call',
  CALL_VERIFIED: 'call_verified',
  PENDING_VERIFICATION: 'pending_verification',
  IN_PROCESS: 'in_process',
  AVAILABLE: 'available',       // Verified & available for work (verified_at is set, green icon)
  UNAVAILABLE: 'unavailable',   // Verified but not available (caregiver or admin toggled off)
  ASSIGNED: 'assigned',         // Currently assigned to work
  REJECTED: 'rejected',
} as const;

export const JobStatus = {
  ACTIVE: 'active',
  CLOSED: 'closed',
} as const;

export const JobResponse = {
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
  MORE_DETAILS: 'more_details',
} as const;

export const Gender = {
  MALE: 'male',
  FEMALE: 'female',
  OTHER: 'other',
} as const;

export const Language = {
  HINDI: 'hindi',
  ENGLISH: 'english',
  KANNADA: 'kannada',
  TAMIL: 'tamil',
  TELUGU: 'telugu',
  MALAYALAM: 'malayalam',
  BENGALI: 'bengali',
  GUJARATI: 'gujarati',
  MARATHI: 'marathi',
} as const;

export const ServiceMode = {
  TWENTY_FOUR_HRS_LIVE_IN: '24hrs_live_in',
  TWELVE_HRS_PG: '12hrs_pg',
} as const;

export const Religion = {
  HINDU: 'hindu',
  MUSLIM: 'muslim',
  CHRISTIAN: 'christian',
  OTHERS: 'others',
} as const;

export const WorkType = {
  COMPANION_CARE: 'companion_care',
  BEDSIDE_CARE: 'bedside_care',
  CRITICAL_CARE: 'critical_care',
} as const;

export const SalaryRanges = {
  COMPANION_CARE: { min: 25000, max: 30000 },
  BEDSIDE_CARE: { min: 28000, max: 35000 },
  CRITICAL_CARE: { min: 30000, max: 45000 },
} as const;

export const City = {
  BANGALORE: 'bangalore',
  MUMBAI: 'mumbai',
  HYDERABAD: 'hyderabad',
  CHENNAI: 'chennai',
  PUNE: 'pune',
  DELHI: 'delhi',
  GURGAON: 'gurgaon',
} as const;

export const Qualification = {
  BSC_GNM_COMPLETED: 'bsc_gnm_completed',
  ANM_COMPLETED: 'anm_completed',
  BSC_GNM_ANM_BACKLOG: 'bsc_gnm_anm_backlog',
  BSC_GNM_ANM_STUDENT: 'bsc_gnm_anm_student',
  NON_NURSING: 'non_nursing',
} as const;

export const AuditAction = {
  REGISTRATION: 'registration',
  LOGIN: 'login',
  CALL_VERIFIED: 'call_verified',
  ADVANCED_DETAILS_SUBMITTED: 'advanced_details_submitted',
  PROFILE_UPDATED: 'profile_updated',
  STATUS_CHANGED: 'status_changed',
  CODE_CHANGED: 'code_changed',
  SERVICE_MODE_ASSIGNED: 'service_mode_assigned',
  ADMIN_EDIT_PROFILE: 'admin_edit_profile',
  ADMIN_NOTE_ADDED: 'admin_note_added',
  ADMIN_CREATED: 'admin_created',
  ADMIN_DEACTIVATED: 'admin_deactivated',
  PHONE_CHANGED: 'phone_changed',
  EDITS_ACKNOWLEDGED: 'edits_acknowledged',
  WORK_TYPE_ASSIGNED: 'work_type_assigned',
  JOB_POSTED: 'job_posted',
  JOB_CLOSED: 'job_closed',
  JOB_RESPONSE: 'job_response',
} as const;

export const UserRole = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  CAREGIVER: 'caregiver',
} as const;
```

#### `packages/shared-constants/src/validation.ts`:
```typescript
export const Validation = {
  PHONE_REGEX: /^\+91[6-9]\d{9}$/,
  NAME_REGEX: /^[a-zA-Z\s]+$/,
  NAME_MAX_LENGTH: 100,
  CODE_LENGTH: 4,
  CODE_REGEX: /^\d{4}$/,
  AGE_MIN: 18,
  AGE_MAX: 65,
  ADDRESS_MAX_LENGTH: 500,
  REJECTION_MESSAGE_MAX_LENGTH: 1000,
  NOTES_MAX_LENGTH: 500,
  FILE_MAX_SIZE_BYTES: 10 * 1024 * 1024, // 10MB
  MAX_OTHER_DOCUMENTS: 3,
  PAGINATION_DEFAULT_LIMIT: 20,
  PAGINATION_MAX_LIMIT: 100,
} as const;
```

#### `packages/vitacare_shared/lib/constants/enums.dart` (Dart mirror):
```dart
class VerificationStatus {
  static const pendingCall = 'pending_call';
  static const callVerified = 'call_verified';
  static const pendingVerification = 'pending_verification';
  static const inProcess = 'in_process';
  static const available = 'available';       // Verified & available (green icon)
  static const unavailable = 'unavailable';   // Verified but not available (toggled off)
  static const assigned = 'assigned';         // Currently assigned to work
  static const rejected = 'rejected';

  static const all = [pendingCall, callVerified, pendingVerification, inProcess, available, unavailable, assigned, rejected];
}

class JobStatus {
  static const active = 'active';
  static const closed = 'closed';

  static const all = [active, closed];
}

class JobResponseType {
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const moreDetails = 'more_details';

  static const all = [accepted, rejected, moreDetails];
}

class Gender {
  static const male = 'male';
  static const female = 'female';
  static const other = 'other';

  static const all = [male, female, other];
}

class Language {
  static const hindi = 'hindi';
  static const english = 'english';
  static const kannada = 'kannada';
  static const tamil = 'tamil';
  static const telugu = 'telugu';
  static const malayalam = 'malayalam';
  static const bengali = 'bengali';
  static const gujarati = 'gujarati';
  static const marathi = 'marathi';

  static const all = [hindi, english, kannada, tamil, telugu, malayalam, bengali, gujarati, marathi];

  /// Display names for UI
  static const displayNames = {
    hindi: 'Hindi',
    english: 'English',
    kannada: 'Kannada',
    tamil: 'Tamil',
    telugu: 'Telugu',
    malayalam: 'Malayalam',
    bengali: 'Bengali',
    gujarati: 'Gujarati',
    marathi: 'Marathi',
  };
}

class ServiceMode {
  static const twentyFourHrsLiveIn = '24hrs_live_in';
  static const twelveHrsPg = '12hrs_pg';

  static const all = [twentyFourHrsLiveIn, twelveHrsPg];

  static const displayNames = {
    twentyFourHrsLiveIn: '24Hrs (Live-In)',
    twelveHrsPg: '12Hrs (Nearby PG)',
  };
}

class Religion {
  static const hindu = 'hindu';
  static const muslim = 'muslim';
  static const christian = 'christian';
  static const others = 'others';

  static const all = [hindu, muslim, christian, others];

  static const displayNames = {
    hindu: 'Hindu',
    muslim: 'Muslim',
    christian: 'Christian',
    others: 'Others',
  };
}

class WorkType {
  static const companionCare = 'companion_care';
  static const bedsideCare = 'bedside_care';
  static const criticalCare = 'critical_care';

  static const all = [companionCare, bedsideCare, criticalCare];

  static const displayNames = {
    companionCare: 'Companion Care',
    bedsideCare: 'Bedside Care (includes diaper change)',
    criticalCare: 'Critical Care',
  };
}

class City {
  static const bangalore = 'bangalore';
  static const mumbai = 'mumbai';
  static const hyderabad = 'hyderabad';
  static const chennai = 'chennai';
  static const pune = 'pune';
  static const delhi = 'delhi';
  static const gurgaon = 'gurgaon';

  static const all = [bangalore, mumbai, hyderabad, chennai, pune, delhi, gurgaon];

  static const displayNames = {
    bangalore: 'Bangalore',
    mumbai: 'Mumbai',
    hyderabad: 'Hyderabad',
    chennai: 'Chennai',
    pune: 'Pune',
    delhi: 'Delhi',
    gurgaon: 'Gurgaon',
  };
}

// ... same pattern for Qualification, AuditAction, UserRole
```

### 2.3 Shared UI Package — Scope Limitations

The caregiver app is a **mobile app** and the admin dashboard is a **web app**. These have fundamentally different UI patterns (touch vs mouse, single-column vs multi-column, spacious vs dense). The shared UI package is therefore limited to **design tokens and platform-agnostic micro-widgets only**.

#### What IS shared (`packages/vitacare_ui`):

| Shared | Why |
|--------|-----|
| Color palette | Brand consistency |
| Typography (font family, weight scale) | Brand consistency |
| Spacing base unit (4px grid) | Consistent visual rhythm |
| `VitaStatusBadge` | Same visual for status in both apps |
| `VitaMultiSelectChips` | Same selection pattern in both apps |
| `VitaLoadingIndicator` | Consistent loading UX |
| `VitaOfflineBanner` | Same offline visual (mobile only, but harmless to include) |

#### What is NOT shared (each app implements its own):

| Not Shared | Why |
|------------|-----|
| Page layouts / scaffolds | Mobile = stack nav; Web = sidebar + content |
| Navigation components | Bottom nav (mobile) vs sidebar (web) |
| Form layouts | Mobile = full-screen forms; Web = inline/modal forms |
| Data tables | Web-only component |
| Bottom sheets, drawers | Mobile-only component |
| Buttons (sizing/padding) | Different tap targets: 48px mobile vs 36px web |
| Text fields (sizing/padding) | Different density requirements |
| Responsive logic | Different breakpoint strategies |

**`packages/vitacare_ui/lib/theme/app_colors.dart`:**
```dart
import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFDBEAFE);
  static const primaryDark = Color(0xFF1E40AF);

  // Status
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);
  static const info = Color(0xFF0891B2);

  // Verification status colors
  static const statusPendingCall = Color(0xFFF59E0B);
  static const statusCallVerified = Color(0xFF8B5CF6);
  static const statusPendingVerification = Color(0xFFF97316);
  static const statusInProcess = Color(0xFF06B6D4);
  static const statusAvailable = Color(0xFF16A34A);   // Green — verified & available
  static const statusAssigned = Color(0xFF2563EB);    // Blue — currently assigned
  static const statusRejected = Color(0xFFDC2626);

  // Neutral
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}
```

**`packages/vitacare_ui/lib/theme/app_spacing.dart`:**
```dart
/// Base spacing unit: 4px. All spacing derives from this.
class AppSpacing {
  static const double unit = 4.0;
  static const double xs = 4.0;    // 1 unit
  static const double sm = 8.0;    // 2 units
  static const double md = 16.0;   // 4 units
  static const double lg = 24.0;   // 6 units
  static const double xl = 32.0;   // 8 units
  static const double xxl = 48.0;  // 12 units
}
```

**Each app builds its OWN ThemeData** using the shared colors/spacing as inputs. The shared package does NOT export a complete `ThemeData` object because mobile and web need different text sizes, input decorations, and component themes.

**Widget naming:** Shared widgets are prefixed with `Vita` (e.g., `VitaStatusBadge`). App-specific widgets use no prefix or an app-specific prefix.

**DO NOT:**
- Do NOT put full `ThemeData` in the shared package. Each app constructs its own theme.
- Do NOT put layout/scaffold widgets in the shared package.
- Do NOT put button or text field widgets in the shared package (density differs too much).
- Do NOT assume both apps will look the same. They share brand identity (colors, fonts), not UX patterns.

### 2.4 Dependency Rules

| Package | Can depend on |
|---------|--------------|
| `packages/shared-constants` | Nothing (leaf node, TypeScript only) |
| `packages/vitacare_shared` | Nothing (leaf node, pure Dart — no Flutter import) |
| `packages/vitacare_ui` | `vitacare_shared` (for enums in status badge), `flutter` |
| `apps/api` | `shared-constants` |
| `apps/caregiver-app` | `vitacare_shared`, `vitacare_ui` |
| `apps/admin-web` | `vitacare_shared`, `vitacare_ui` |

**DO NOT:**
- Do NOT create circular dependencies between packages.
- Do NOT import from `apps/` into `packages/`. Packages must not know about apps.
- Do NOT import Flutter (`package:flutter`) in `vitacare_shared`. It must be pure Dart.
- Do NOT put API-calling logic in shared packages. Each app manages its own HTTP client.
- Do NOT use code generation (build_runner, json_serializable) in shared packages — keep models simple with manual `fromJson`/`toJson` factory methods for transparency and predictability.
- Do NOT put full ThemeData, buttons, text fields, or layout widgets in `vitacare_ui`. Mobile and web have different density and interaction models.

---

## 3. Authentication & Authorization

### 3.1 Caregiver Authentication

#### Auth Strategy: Custom JWT (No Supabase Auth)

All authentication is handled by the NestJS backend using custom JWT tokens. Supabase is used only for database, storage, and realtime — not for auth. This avoids complexity of dual-token validation and Supabase Auth's OTP requirement for phone login.

#### Registration: Phone + 4-Digit Code (Stage 1)

- Caregiver registers with phone number, basic details, and a self-chosen 4-digit numeric code.
- Backend creates a row in `users` table; code is hashed (bcrypt) and stored in `code_hash` at creation.
- Backend generates and issues a custom JWT immediately.
- **Login (from registration onward):** Caregiver enters phone number + 4-digit code → backend looks up user in `users` table, verifies the code hash → issues JWT.
- **Security model:** The code is collected at registration (not deferred to Stage 3) so every caregiver login, from the very first session, is phone + code — there is no phone-only fallback to reason about.
- **Session persistence:** JWT stored locally on device. Caregiver stays logged in until token expires or they log out.

**DO NOT:**
- Do NOT use Supabase Auth for any accounts (caregiver or admin).
- Do NOT implement OTP verification at registration or login.
- Do NOT store any sensitive data (Aadhaar, address) until Stage 3 (advanced details) — the login code is not sensitive profile data and is fine to collect at Stage 1.
- Do NOT reintroduce a phone-only login endpoint.

#### Stage 3: Advanced Details (Code Unchanged)

- After admin marks "Call Verified", caregiver fills advanced details (qualification, religion, family/address info, documents). The login code is NOT part of this step — it was already set at registration.
- Admin can change a caregiver's code at any time via `/admin/caregivers/:id/code`.

#### Token Structure

```json
{
  "sub": "user_uuid",
  "role": "caregiver",
  "phone": "+91XXXXXXXXXX",
  "iat": 1234567890,
  "exp": 1234571490
}
```

- Access token TTL: 1 hour.
- Refresh token TTL: 30 days.
- Refresh tokens stored in a `refresh_tokens` table and rotated on each use.
- JWT signed with a server-side secret (`JWT_SECRET` env var).

#### Code Hashing (Caregiver)

- Algorithm: bcrypt with salt rounds = 10.
- Stored in `users.code_hash`, set at registration (not nullable for caregiver accounts).
- Code is a 4-digit numeric PIN (0000–9999).

#### Refresh Token Storage

```sql
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
```

**DO NOT:**
- Do NOT store refresh tokens in plain text. Store bcrypt hash of the token.
- Do NOT reuse refresh tokens. Each use generates a new token and revokes the old one.
- Do NOT keep expired/revoked tokens forever. Clean up periodically (but not via cron — do it lazily on login).

### 3.2 Admin Authentication

- Email + password only.
- **Same custom JWT system as caregivers** — no Supabase Auth for anyone.
- Admin password stored as bcrypt hash in `users.password_hash`.
- Admin logs in via `POST /auth/login/email` → receives custom JWT with `role: "admin"` or `role: "super_admin"`.
- No phone-based login for admins.

**Why no Supabase Auth at all:** Using a single auth system (custom JWT) avoids the complexity of validating two different token types in the backend. Supabase is used purely as database + storage + realtime — not for auth.

### 3.3 Role-Based Authorization

| Endpoint Prefix | Allowed Roles |
|----------------|---------------|
| `/auth/*` | Public (no auth) |
| `/caregiver/*` | `caregiver` |
| `/admin/caregivers/*` | `admin`, `super_admin` |
| `/admin/dashboard/*` | `admin`, `super_admin` |
| `/admin/audit-logs/*` | `admin`, `super_admin` |
| `/admin/users/*` | `super_admin` only |

### 3.4 Guard Implementation

```typescript
// Pseudocode for role guard
@Injectable()
export class RolesGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.get<string[]>('roles', context.getHandler());
    const user = context.switchToHttp().getRequest().user;
    return requiredRoles.includes(user.role);
  }
}
```

**DO NOT:**
- Do NOT allow caregivers to access any `/admin/*` endpoint.
- Do NOT allow `admin` role to access `/admin/users/*` (Super Admin only).
- Do NOT expose user passwords or internal IDs in API responses to caregivers.

---

## 4. Database Schema

### 4.1 Complete Schema

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS TABLE
-- ============================================
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE,
  phone VARCHAR(20) UNIQUE NOT NULL,
  password_hash VARCHAR(255),             -- NULL for caregivers, set for admins only
  code_hash VARCHAR(255),                 -- NULL for admins, set at registration for caregivers (4-digit numeric code)
  full_name VARCHAR(100) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('super_admin', 'admin', 'caregiver')),
  is_active BOOLEAN DEFAULT true,
  fcm_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_is_active ON users(is_active);

-- ============================================
-- CAREGIVER PROFILES TABLE
-- ============================================
CREATE TABLE caregiver_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  selfie_photo_url TEXT,
  gender VARCHAR(30) NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  age INTEGER NOT NULL CHECK (age >= 18 AND age <= 65),
  highest_qualification VARCHAR(100),
  qualification_document_url TEXT,
  aadhaar_document_url TEXT,
  religion VARCHAR(20) CHECK (religion IN ('hindu', 'muslim', 'christian', 'others')),
  father_name VARCHAR(100),
  father_phone VARCHAR(20),
  current_address TEXT CHECK (char_length(current_address) <= 500),
  other_document_urls JSONB DEFAULT '[]',
  salary DECIMAL(10, 2) CHECK (salary >= 0),  -- Admin-assigned, visible to caregiver
  notes TEXT CHECK (char_length(notes) <= 500),
  terms_accepted BOOLEAN DEFAULT false,
  verification_status VARCHAR(30) DEFAULT 'pending_call'
    CHECK (verification_status IN (
      'pending_call',
      'call_verified',
      'pending_verification',
      'in_process',
      'available',
      'unavailable',
      'assigned',
      'rejected'
    )),
  rejection_message TEXT,
  call_verified_at TIMESTAMPTZ,
  call_verified_by UUID REFERENCES users(id),  -- App validates this is admin/super_admin
  advanced_details_completed BOOLEAN DEFAULT false,
  has_pending_edits BOOLEAN DEFAULT false,
  submitted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users(id),      -- App validates this is admin/super_admin
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_caregiver_profiles_status ON caregiver_profiles(verification_status);
CREATE INDEX idx_caregiver_profiles_created_at ON caregiver_profiles(created_at);

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

-- ============================================
-- CAREGIVER PREFERRED CITIES TABLE
-- Caregiver can select multiple preferred cities (multi-select, not a
-- single value) — same many-to-many pattern as caregiver_languages.
-- ============================================
CREATE TABLE caregiver_preferred_cities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  city VARCHAR(30) NOT NULL CHECK (city IN (
    'bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon'
  )),
  UNIQUE(profile_id, city)
);

CREATE INDEX idx_caregiver_preferred_cities_profile ON caregiver_preferred_cities(profile_id);

-- ============================================
-- CAREGIVER SERVICE MODES TABLE
-- ============================================
CREATE TABLE caregiver_service_modes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  service_mode VARCHAR(20) NOT NULL CHECK (service_mode IN ('24hrs_live_in', '12hrs_pg')),
  UNIQUE(profile_id, service_mode)
);

CREATE INDEX idx_caregiver_service_modes_profile ON caregiver_service_modes(profile_id);

-- ============================================
-- CAREGIVER WORK TYPES TABLE (admin-assigned)
-- ============================================
CREATE TABLE caregiver_work_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  work_type VARCHAR(30) NOT NULL CHECK (work_type IN ('companion_care', 'bedside_care', 'critical_care')),
  assigned_by UUID NOT NULL REFERENCES users(id),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id, work_type)
);

CREATE INDEX idx_caregiver_work_types_profile ON caregiver_work_types(profile_id);

-- ============================================
-- ADMIN NOTES TABLE
-- ============================================
CREATE TABLE admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES users(id),
  internal_notes TEXT,
  rate_24hrs_live_in DECIMAL(10, 2) CHECK (rate_24hrs_live_in >= 0),
  rate_12hrs_pg DECIMAL(10, 2) CHECK (rate_12hrs_pg >= 0),
  availability_remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id)
);

-- ============================================
-- JOBS TABLE (admin-posted job listings)
-- ============================================
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_type VARCHAR(30) NOT NULL CHECK (work_type IN ('companion_care', 'bedside_care', 'critical_care')),
  city VARCHAR(30) NOT NULL CHECK (city IN ('bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon')),
  description TEXT NOT NULL,
  duty_timings VARCHAR(20) NOT NULL CHECK (duty_timings IN ('24hrs_live_in', '12hrs_pg')),
  language VARCHAR(50) NOT NULL CHECK (language IN ('hindi', 'english', 'kannada', 'tamil', 'telugu', 'malayalam', 'bengali', 'gujarati', 'marathi')),
  gender_needed VARCHAR(10) NOT NULL CHECK (gender_needed IN ('male', 'female')),
  religion VARCHAR(20) NOT NULL CHECK (religion IN ('hindu', 'muslim', 'christian', 'others')),
  status VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  posted_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);

-- ============================================
-- JOB RESPONSES TABLE (caregiver responses to jobs)
-- ============================================
CREATE TABLE job_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  response VARCHAR(20) NOT NULL CHECK (response IN ('accepted', 'rejected', 'more_details')),
  message TEXT,                           -- Question text when response is 'more_details'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(job_id, profile_id)
);

CREATE INDEX idx_job_responses_job ON job_responses(job_id);
CREATE INDEX idx_job_responses_profile ON job_responses(profile_id);

-- ============================================
-- AUDIT LOGS TABLE
-- ============================================
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  target_user_id UUID REFERENCES users(id),
  action VARCHAR(50) NOT NULL CHECK (action IN (
    'registration',
    'login',
    'call_verified',
    'advanced_details_submitted',
    'profile_updated',
    'status_changed',
    'code_changed',
    'service_mode_assigned',
    'admin_edit_profile',
    'admin_note_added',
    'admin_created',
    'admin_deactivated',
    'phone_changed',
    'edits_acknowledged',
    'work_type_assigned',
    'job_posted',
    'job_closed',
    'job_response'
  )),
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

### 4.2 Seed Script (Super Admin)

```sql
-- Run once during initial setup
-- Password hash must be generated by the application (bcrypt, 10 salt rounds)
-- Example: password "admin123" → hash generated at seed time via a script
INSERT INTO users (id, email, phone, password_hash, full_name, role, is_active)
VALUES (
  gen_random_uuid(),
  'vitacasahealthindia@gmail.com',
  '+917259255869',
  '$2b$10$GENERATED_HASH_HERE',  -- Generate via: npx bcrypt-cli hash "your_password"
  'Super Admin',
  'super_admin',
  true
);
```

**Seed process:** Run a Node.js script (not raw SQL) that prompts for the Super Admin password, hashes it with bcrypt, and inserts the row. Never commit a real password hash to source control.

**DO NOT:**
- Do NOT store Aadhaar numbers as plain text anywhere in the database. Only store the document URL.
- Do NOT add columns for data that belongs in V2 (family, patient, assignments, payments).
- V2 will add `'family'` to the `users.role` CHECK constraint via a database migration. V1 schema does not include it.
- Do NOT create triggers or stored procedures — all business logic lives in NestJS.

---

## 5. File Storage

### 5.1 Supabase Storage Buckets

| Bucket | Access | Purpose |
|--------|--------|---------|
| `caregiver-documents` | Private (signed URLs) | All caregiver uploads |

### 5.2 File Path Convention

```
caregiver-documents/
└── {profile_id}/
    ├── selfie.{ext}
    ├── qualification.{ext}
    ├── aadhaar.{ext}
    ├── other_1.{ext}
    ├── other_2.{ext}
    └── other_3.{ext}
```

- `{ext}` is the original file extension preserved from upload.
- If a file is re-uploaded, the old file is overwritten (same path).

### 5.3 Upload Rules

| Rule | Value |
|------|-------|
| Max file size | 10 MB per file |
| Allowed types | Any (no file type restriction) |
| Max "other" documents | 3 files |
| Selfie source | Camera capture only (not gallery) |
| Signed URL expiry | 1 hour |

### 5.4 Upload Flow

1. Client calls `POST /caregiver/profile/documents` with multipart form data.
2. Backend validates file size (reject if > 10MB).
3. Backend uploads to Supabase Storage at the correct path.
4. Backend stores the file path (not full URL) in the database.
5. When documents are requested, backend generates a signed URL with 1-hour expiry.

**DO NOT:**
- Do NOT validate file MIME type or extension. Accept any file.
- Do NOT allow gallery selection for selfie. Only camera capture.
- Do NOT serve files without signed URLs. All document access must be time-limited.
- Do NOT allow more than 3 "other" documents.
- Do NOT store Supabase Storage full URLs in the database. Store only the relative path.

---

## 6. API Specification

### 6.1 Base URL

```
Production: https://api.vitacasahealth.in/v1
Development: http://localhost:3000/v1
```

### 6.2 Response Format

All responses follow this structure:

```json
// Success
{
  "success": true,
  "data": { ... },
  "meta": {              // Only for paginated responses
    "page": 1,
    "limit": 20,
    "total": 45,
    "totalPages": 3
  }
}

// Error
{
  "success": false,
  "error": {
    "code": "AUTH_001",
    "message": "Phone number is already registered"
  }
}
```

**DO NOT:**
- Do NOT return raw database errors to clients.
- Do NOT include stack traces in production responses.
- Do NOT return `null` for the `data` field on success — use an empty object `{}` or appropriate type.
- Do NOT include internal IDs in caregiver-facing responses that aren't needed by the client.

### 6.3 Authentication Endpoints

#### POST `/auth/register`

Register a new caregiver (Stage 1).

**Request:**
```json
{
  "phone": "+919876543210",
  "full_name": "Ramesh Kumar",
  "gender": "male",
  "age": 32,
  "languages": ["hindi", "english"],
  "code": "1234"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "profile_id": "uuid",
    "access_token": "jwt_token",
    "refresh_token": "refresh_token",
    "verification_status": "pending_call"
  }
}
```

**Validation Rules:**
- `phone`: Required, must match `/^\+91[6-9]\d{9}$/`, must be unique.
- `full_name`: Required, 1-100 characters, alphabetic + spaces only.
- `gender`: Required, must be one of: `male`, `female`, `other`.
- `age`: Required, integer, 18-65 inclusive.
- `languages`: Required, array, min 1 item, each must be valid language enum.
- `code`: Required, exactly 4 digits, numeric only (`/^\d{4}$/`). This is the caregiver's login code from their very first session — used with `/auth/login/code` for every subsequent login. Hashed (bcrypt) and stored in `code_hash` at creation.

**Note:** Selfie is uploaded separately via `POST /caregiver/profile/selfie` immediately after registration.

---

#### POST `/auth/login/code`

Login with phone + 4-digit code. The code is set at registration, so this is the only caregiver login endpoint — there is no phone-only login.

**Request:**
```json
{
  "phone": "+919876543210",
  "code": "1234"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "access_token": "jwt_token",
    "refresh_token": "refresh_token",
    "verification_status": "available",
    "advanced_details_completed": true
  }
}
```

---

#### POST `/auth/login/email`

Login with email + password (admin only).

**Request:**
```json
{
  "email": "admin@vitacasahealth.in",
  "password": "password123"
}
```

**Response (200):** Same structure as phone login.

---

#### POST `/auth/refresh`

Refresh access token.

**Request:**
```json
{
  "refresh_token": "current_refresh_token"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "new_jwt_token",
    "refresh_token": "new_refresh_token"
  }
}
```

---

#### POST `/auth/logout`

**Headers:** `Authorization: Bearer <token>`

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Logged out successfully"
  }
}
```

---

### 6.4 Caregiver Profile Endpoints

#### GET `/caregiver/profile`

Get own full profile.

**Headers:** `Authorization: Bearer <token>`

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "profile_id": "uuid",
    "full_name": "Ramesh Kumar",
    "phone": "+919876543210",
    "gender": "male",
    "age": 32,
    "selfie_photo_url": "https://signed-url...",
    "languages": ["hindi", "english"],
    "service_modes": ["24hrs_live_in"],
    "work_types": ["companion_care", "bedside_care"],
    "salary": 28000.00,
    "highest_qualification": "bsc_gnm_completed",
    "religion": "hindu",
    "father_name": "Suresh Kumar",
    "father_phone": "+919876500001",
    "qualification_document_url": "https://signed-url...",
    "aadhaar_document_url": "https://signed-url...",
    "other_document_urls": ["https://signed-url..."],
    "current_address": "123, MG Road, Bangalore",
    "terms_accepted": true,
    "verification_status": "available",
    "rejection_message": null,
    "advanced_details_completed": true,
    "preferred_cities": ["bangalore", "mumbai"],
    "notes": "Available for night shifts",
    "created_at": "2026-08-01T10:00:00Z"
  }
}
```

**Notes:**
- All fields are always returned in the response. Fields not yet set return `null`. No fields are omitted.
- Document URLs are signed URLs with 1-hour expiry (or `null` if not uploaded).
- If `verification_status` is `pending_call`, advanced fields will be `null`.
- If `advanced_details_completed` is `false`, advanced fields will be `null`.

---

#### PUT `/caregiver/profile/basic`

Update basic profile fields.

**Request:**
```json
{
  "age": 33,
  "languages": ["hindi", "english", "kannada"]
}
```

full_name and gender are NOT accepted here — both are locked from self-edit past registration; only an admin can change them.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Profile updated",
    "has_pending_edits": true,
    "verification_status": "available"
  }
}
```

Note: `verification_status` remains unchanged. It reflects the current status, NOT a reset.

**Side effects:**
- Audit log entry created with before/after values.
- Email notification sent to admin with changed fields.
- Profile is flagged as `has_pending_edits = true` in the database.
- **Status does NOT change automatically.** Admin reviews the edits and manually decides whether to re-verify.

**DO NOT:**
- Do NOT auto-reset verification status on profile edit.
- Do NOT block the caregiver from using the app while edits are pending review.
- Each profile edit re-sets `has_pending_edits = true` even if previously acknowledged.
- Profile edits for caregivers in `available`/`assigned` status flag for review. For `rejected` status, edits trigger re-submission flow instead.

---

#### PUT `/caregiver/profile/advanced`

Submit advanced details (only accessible after `call_verified` status).

**Request:**
```json
{
  "highest_qualification": "bsc_gnm_completed",
  "religion": "hindu",
  "father_name": "Suresh Kumar",
  "father_phone": "+919876500001",
  "current_address": "123, MG Road, Bangalore 560001",
  "preferred_cities": ["bangalore", "mumbai"],
  "notes": "Available for night shifts",
  "terms_accepted": true
}
```

**Validation Rules:**
- `highest_qualification`: Required, must be one of: `bsc_gnm_completed`, `anm_completed`, `bsc_gnm_anm_backlog`, `bsc_gnm_anm_student`, `non_nursing`.
- `religion`: Required, must be one of: `hindu`, `muslim`, `christian`, `others`.
- `father_name`: Optional. If provided, 1-100 characters, alphabetic + spaces only.
- `father_phone`: Optional. If provided, must match `/^\+91[6-9]\d{9}$/`.
- `current_address`: Optional. If provided, max 500 characters.
- `preferred_cities`: Optional array (multi-select). If provided, each value must be one of: `bangalore`, `mumbai`, `hyderabad`, `chennai`, `pune`, `delhi`, `gurgaon`. Omitted or `[]` means no preference.
- `notes`: Optional, max 500 characters.
- `terms_accepted`: Required, must be `true`.

**Preconditions:**
- Caregiver must have `verification_status = 'call_verified'` OR `'rejected'` (re-submission).
- Aadhaar document must already be uploaded. Selfie is already guaranteed by
  registration (Stage 1). Qualification document and "other" documents are
  optional — not required to submit.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Advanced details submitted",
    "verification_status": "pending_verification"
  }
}
```

**Side effects:**
- `advanced_details_completed` set to `true`.
- `verification_status` changed to `pending_verification`.
- `submitted_at` set to current timestamp.
- Email notification sent to admin.
- Audit log entry created.

**DO NOT:**
- Do NOT allow this endpoint if status is not `call_verified` or `rejected`.
- Do NOT allow submission if Aadhaar is not uploaded.
- Do NOT accept a `code` field here — the login code is set once, at registration (`POST /auth/register`). A `code` field in this request body is rejected by the whitelist validator (`GEN_001`).

---

#### POST `/caregiver/profile/selfie`

Upload selfie photo. Multipart form data.

**Headers:** `Authorization: Bearer <token>`, `Content-Type: multipart/form-data`

**Request:** Form field `file` with the image data.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Selfie uploaded",
    "file_path": "caregiver-documents/{profile_id}/selfie.jpg"
  }
}
```

**Validation:**
- File size must be <= 10MB.
- No file type restriction.

---

#### POST `/caregiver/profile/documents`

Upload qualification doc, Aadhaar, or other documents. Multipart form data.

**Headers:** `Authorization: Bearer <token>`, `Content-Type: multipart/form-data`

**Request:** Form fields:
- `file`: The file data.
- `document_type`: One of `qualification`, `aadhaar`, `other`.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Document uploaded",
    "document_type": "aadhaar",
    "file_path": "caregiver-documents/{profile_id}/aadhaar.pdf"
  }
}
```

**Rules:**
- `qualification` and `aadhaar`: One file each, re-upload overwrites.
- `other`: Up to 3 files. Subsequent uploads are named `other_1`, `other_2`, `other_3`.
- If 3 "other" files already exist and a 4th is attempted, return error.

---

#### GET `/caregiver/verification-status`

**Response (200):**
```json
{
  "success": true,
  "data": {
    "verification_status": "pending_verification",
    "rejection_message": null,
    "submitted_at": "2026-08-01T10:00:00Z",
    "verified_at": null
  }
}
```

---

#### PATCH `/caregiver/availability-status`

Toggle availability status. Caregiver can switch between `available` and `unavailable`.

This is also triggered by the daily availability reminder notification — caregiver taps "Yes" (available) or "No" (unavailable).

**Precondition:** Status must be `available` or `unavailable`. Cannot toggle if `assigned` (must be unassigned by admin first), or if in any pre-verification status.

**Request:**
```json
{
  "status": "unavailable"
}
```

**Validation:**
- `status`: Required, must be `available` or `unavailable`.
- Current status must be `available` or `unavailable`. If `assigned` → return error "Cannot change availability while assigned to work."

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Availability updated",
    "verification_status": "unavailable"
  }
}
```

**Side effects:**
- Audit log entry created.
- If toggled to `unavailable`, caregiver will NOT appear in admin's "available for assignment" pool.

---

#### PUT `/caregiver/fcm-token`

Update the FCM token for push notifications.

**Request:**
```json
{
  "token": "fcm_token_string"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "FCM token updated"
  }
}
```

**When to call:** After registration, on each app launch, and when FCM token refreshes.

---

### 6.5 Admin Endpoints

#### GET `/admin/dashboard/stats`

**Response (200):**
```json
{
  "success": true,
  "data": {
    "total_caregivers": 150,
    "pending_call": 12,
    "call_verified": 5,
    "pending_verification": 8,
    "in_process": 3,
    "available": 80,
    "unavailable": 20,
    "assigned": 10,
    "rejected": 12,
    "pending_edits_count": 3,
    "new_registrations_24h": 4,
    "new_registrations_7d": 18
  }
}
```

---

#### GET `/admin/caregivers`

Paginated, filterable list.

**Query Parameters:**
- `page` (default: 1)
- `limit` (default: 20, max: 100)
- `sort` (default: `created_at`, options: `created_at`, `full_name`, `age`)
- `order` (default: `desc`, options: `asc`, `desc`)
- `search` (searches: full_name, phone)
- `status` (filter: `pending_call`, `call_verified`, `pending_verification`, `in_process`, `available`, `unavailable`, `assigned`, `rejected`)
- `qualification` (filter by qualification)
- `language` (filter by language, comma-separated for multiple)
- `service_mode` (filter: `24hrs_live_in`, `12hrs_pg`)
- `work_type` (filter: `companion_care`, `bedside_care`, `critical_care`)
- `from_date` (ISO date, registration date from)
- `to_date` (ISO date, registration date to)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "user_id": "uuid",
      "profile_id": "uuid",
      "full_name": "Ramesh",
      "full_name": "Kumar",
      "phone": "+919876543210",
      "gender": "male",
      "age": 32,
      "highest_qualification": "bsc_gnm_completed",
      "service_modes": ["24hrs_live_in"],
      "work_types": ["companion_care"],
      "verification_status": "pending_verification",
      "created_at": "2026-08-01T10:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "limit": 20,
    "total": 45,
    "totalPages": 3
  }
}
```

---

#### GET `/admin/caregivers/:id`

Full caregiver detail with signed document URLs.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "profile_id": "uuid",
    "full_name": "Ramesh Kumar",
    "phone": "+919876543210",
    "gender": "male",
    "age": 32,
    "selfie_photo_url": "https://signed-url...",
    "languages": ["hindi", "english"],
    "service_modes": ["24hrs_live_in"],
    "work_types": ["companion_care", "bedside_care"],
    "salary": 28000.00,
    "highest_qualification": "bsc_gnm_completed",
    "religion": "hindu",
    "father_name": "Suresh Kumar",
    "father_phone": "+919876500001",
    "qualification_document_url": "https://signed-url...",
    "aadhaar_document_url": "https://signed-url...",
    "other_document_urls": ["https://signed-url..."],
    "current_address": "123, MG Road, Bangalore",
    "terms_accepted": true,
    "verification_status": "pending_verification",
    "rejection_message": null,
    "advanced_details_completed": true,
    "preferred_cities": ["bangalore", "mumbai"],
    "notes": null,
    "admin_notes": {
      "internal_notes": "Good candidate, verified docs look clean",
      "rate_24hrs_live_in": 25000.00,
      "rate_12hrs_pg": 15000.00,
      "availability_remarks": "Prefers south Bangalore"
    },
    "created_at": "2026-08-01T10:00:00Z",
    "submitted_at": "2026-08-02T14:00:00Z",
    "verified_at": null
  }
}
```

---

#### PATCH `/admin/caregivers/:id/call-verified`

Mark caregiver as phone-call verified.

**Precondition:** Caregiver must have `verification_status = 'pending_call'`.

**Request:** No body required.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Caregiver marked as call verified",
    "verification_status": "call_verified"
  }
}
```

**Side effects:**
- `verification_status` → `call_verified`.
- `call_verified_at` set to current timestamp.
- `call_verified_by` set to admin user ID.
- Push notification sent to caregiver.
- Email sent to caregiver (if email available — unlikely at this stage, so push only).
- Audit log entry created.

---

#### PATCH `/admin/caregivers/:id/status`

Update verification status (for document review stage).

**Request:**
```json
{
  "status": "available",
  "rejection_message": null
}
```

**Allowed transitions:**
- `pending_verification` → `in_process`
- `pending_verification` → `available` (approves — sets verified_at, caregiver becomes available)
- `pending_verification` → `rejected`
- `in_process` → `available` (approves — sets verified_at, caregiver becomes available)
- `in_process` → `rejected`
- `available` → `pending_verification` (admin manually resets after reviewing edits)
- `rejected` → `pending_verification` (only via caregiver re-submission, NOT admin action)

**DO NOT:**
- Do NOT allow setting status to `pending_call` or `call_verified` via this endpoint.
- Do NOT allow `rejected` → `available` directly (caregiver must re-submit first).
- Do NOT allow `available` → `rejected` directly (must go through `pending_verification` first).

**Validation:**
- `status`: Required, must be `in_process`, `available`, or `rejected`.
- `rejection_message`: Optional, only relevant when status is `rejected`, max 1000 characters.

**Side effects:**
- If `available`: `verified_at` set, `verified_by` set to admin ID. Green icon shown.
- Push notification sent to caregiver.
- Audit log entry created.

---

#### PUT `/admin/caregivers/:id`

Edit caregiver profile (admin override).

**Request:** Any subset of caregiver profile fields.
```json
{
  "full_name": "Ramesh",
  "age": 33,
  "languages": ["hindi", "english", "tamil"]
}
```

**Side effects:**
- Audit log with before/after values.
- Does NOT change verification status (admin edits are trusted).

---

#### POST `/admin/caregivers/:id/notes`

Add or update admin notes for a caregiver.

**Request:**
```json
{
  "internal_notes": "Verified all documents. Candidate seems experienced.",
  "rate_24hrs_live_in": 25000.00,
  "rate_12hrs_pg": 15000.00,
  "availability_remarks": "Prefers morning shifts, south Bangalore area"
}
```

**Validation:**
- `rate_24hrs_live_in`: Optional, decimal, >= 0.
- `rate_12hrs_pg`: Optional, decimal, >= 0.
- `internal_notes`: Optional, no max length.
- `availability_remarks`: Optional, no max length.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Notes saved"
  }
}
```

**Notes are upserted** — if notes already exist for this caregiver, they are updated.

**DO NOT:**
- Do NOT expose admin notes to caregivers via any endpoint.
- Do NOT include admin notes in the caregiver's own profile response.

---

#### PUT `/admin/caregivers/:id/work-types`

Assign work types to a caregiver. Admin-only. Caregivers can view but not modify.

**Request:**
```json
{
  "work_types": ["companion_care", "bedside_care"]
}
```

**Validation:**
- `work_types`: Required, array, min 1, each must be valid work type enum (`companion_care`, `bedside_care`, `critical_care`).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Work types assigned",
    "work_types": ["companion_care", "bedside_care"]
  }
}
```

**Side effects:**
- Replaces all existing work types for this caregiver (full replace, not merge).
- `assigned_by` set to admin user ID.
- Audit log entry created.

**DO NOT:**
- Do NOT allow caregivers to modify work types. Read-only for them.
- Do NOT expose `assigned_by` to caregiver-facing endpoints.

---

#### PUT `/admin/caregivers/:id/service-modes`

Assign service modes to a caregiver. Admin-only. Caregivers can view but not modify.

**Request:**
```json
{
  "service_modes": ["24hrs_live_in", "12hrs_pg"]
}
```

**Validation:**
- `service_modes`: Required, array, min 1, each must be valid service mode enum (`24hrs_live_in`, `12hrs_pg`).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Service modes assigned",
    "service_modes": ["24hrs_live_in", "12hrs_pg"]
  }
}
```

**Side effects:**
- Replaces all existing service modes for this caregiver.
- Audit log entry created.

**DO NOT:**
- Do NOT allow caregivers to modify service modes. Read-only for them.

---

#### PATCH `/admin/caregivers/:id/salary`

Set or update a caregiver's salary. Admin-only. Visible to caregiver on their profile.

**Request:**
```json
{
  "salary": 28000.00
}
```

**Validation:**
- `salary`: Required, decimal, >= 0.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Salary updated",
    "salary": 28000.00
  }
}
```

**Side effects:**
- `salary` column updated in `caregiver_profiles`.
- Audit log entry created.

**DO NOT:**
- Do NOT allow caregivers to modify their own salary.

---

#### GET `/admin/caregivers/:id/documents`

Get all document signed URLs for a caregiver.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "selfie_photo_url": "https://signed-url...",
    "qualification_document_url": "https://signed-url...",
    "aadhaar_document_url": "https://signed-url...",
    "other_document_urls": [
      "https://signed-url...",
      "https://signed-url..."
    ]
  }
}
```

---

#### PATCH `/admin/caregivers/:id/acknowledge-edits`

Clear the pending edits flag after admin has reviewed the caregiver's profile changes.

**Precondition:** Caregiver must have `has_pending_edits = true`.

**Request:** No body required.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Edits acknowledged",
    "has_pending_edits": false
  }
}
```

**Side effects:**
- `has_pending_edits` set to `false`.
- Audit log entry created.

---

#### PATCH `/admin/caregivers/:id/phone`

Change a caregiver's phone number (for account recovery when caregiver contacts office with a new number).

**Request:**
```json
{
  "new_phone": "+919876500000"
}
```

**Validation:**
- `new_phone`: Required, must match `/^\+91[6-9]\d{9}$/`, must be unique (not already used by another account).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Phone number updated",
    "old_phone": "+919876543210",
    "new_phone": "+919876500000"
  }
}
```

**Side effects:**
- `users.phone` updated in database.
- Audit log entry with before/after phone values.
- Admin who performed the action is recorded.

**DO NOT:**
- Do NOT allow caregivers to change their own phone number via API. Only admin can do this.
- Do NOT change verification status when phone is updated by admin.

---

#### PATCH `/admin/caregivers/:id/code`

Change a caregiver's 4-digit login code. Admin can reset this at any time.

**Request:**
```json
{
  "code": "5678"
}
```

**Validation:**
- `code`: Required, exactly 4 digits, numeric only (`/^\d{4}$/`).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Code updated"
  }
}
```

**Side effects:**
- `code_hash` updated in `users` table (bcrypt hash of new code).
- Audit log entry created.
- Push notification sent to caregiver: "Your login code has been changed by admin."
- Existing sessions remain valid until token expiry (1 hour). New code required at next login only.

---

#### PATCH `/admin/caregivers/:id/assign`

Mark a caregiver as assigned (admin gave work directly, e.g., via phone call). This is NOT automatically triggered by job posting acceptance — accepting a job only indicates interest. Admin manually assigns work.

**Precondition:** Caregiver must have `verification_status = 'available'`.

**Request:** No body required.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Caregiver marked as assigned",
    "verification_status": "assigned"
  }
}
```

---

#### PATCH `/admin/caregivers/:id/unassign`

Mark an assigned caregiver back as available (assignment completed).

**Precondition:** Caregiver must have `verification_status = 'assigned'`.

**Request:** No body required.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Caregiver marked as available",
    "verification_status": "available"
  }
}
```

---

### 6.6 Job Posting Endpoints

#### POST `/admin/jobs`

Create a new job posting. Sends push notification to ALL caregivers.

**Request:**
```json
{
  "work_type": "bedside_care",
  "city": "bangalore",
  "description": "Elderly patient, 72 years, post hip surgery. Needs assistance with mobility, feeding, and medication reminders.",
  "duty_timings": "24hrs_live_in",
  "language": "kannada",
  "gender_needed": "female",
  "religion": "hindu"
}
```

**Validation:**
- `work_type`: Required, must be one of: `companion_care`, `bedside_care`, `critical_care`.
- `city`: Required, must be valid city enum.
- `description`: Required, free text (about patient and scope of work).
- `duty_timings`: Required, must be `24hrs_live_in` or `12hrs_pg`.
- `language`: Required, must be valid language enum.
- `gender_needed`: Required, must be `male` or `female`.
- `religion`: Required, must be valid religion enum.

**Response (201):**
```json
{
  "success": true,
  "data": {
    "job_id": "uuid",
    "message": "Job posted and notifications sent"
  }
}
```

**Side effects:**
- Job stored in `jobs` table with status `active`.
- Push notification sent to ALL caregivers (background notification — works even if app is closed).
- Notification title: "New Job: Bedside Care - ₹28,000–₹35,000"
- Notification body: "Bangalore | 24Hrs Live-In | IMMEDIATELY APPLY"
- Audit log entry created.

---

#### GET `/admin/jobs`

List all job postings (paginated).

**Query Parameters:**
- `page`, `limit`, `sort`, `order` (standard pagination)
- `status` (filter: `active`, `closed`)
- `work_type` (filter)
- `city` (filter)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "job_id": "uuid",
      "work_type": "bedside_care",
      "city": "bangalore",
      "description": "Elderly patient...",
      "duty_timings": "24hrs_live_in",
      "language": "kannada",
      "gender_needed": "female",
      "religion": "hindu",
      "status": "active",
      "responses_count": { "accepted": 5, "rejected": 2, "more_details": 3 },
      "created_at": "2026-08-03T10:00:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 10, "totalPages": 1 }
}
```

---

#### GET `/admin/jobs/:id`

Get job detail with all caregiver responses.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "job_id": "uuid",
    "work_type": "bedside_care",
    "city": "bangalore",
    "description": "Elderly patient...",
    "duty_timings": "24hrs_live_in",
    "language": "kannada",
    "gender_needed": "female",
    "religion": "hindu",
    "status": "active",
    "posted_by": "Admin One",
    "created_at": "2026-08-03T10:00:00Z",
    "responses": [
      {
        "profile_id": "uuid",
        "full_name": "Ramesh Kumar",
        "phone": "+919876543210",
        "response": "accepted",
        "message": null,
        "responded_at": "2026-08-03T11:00:00Z"
      },
      {
        "profile_id": "uuid",
        "full_name": "Priya Singh",
        "phone": "+919876500000",
        "response": "more_details",
        "message": "What are the patient's mobility limitations?",
        "responded_at": "2026-08-03T11:30:00Z"
      }
    ]
  }
}
```

---

#### PATCH `/admin/jobs/:id/close`

Close a job posting (no more responses accepted).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Job closed",
    "status": "closed"
  }
}
```

---

#### GET `/caregiver/jobs`

List active job postings for caregiver to view and respond.

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "job_id": "uuid",
      "work_type": "bedside_care",
      "salary_range": { "min": 28000, "max": 35000 },
      "city": "bangalore",
      "description": "Elderly patient...",
      "duty_timings": "24hrs_live_in",
      "language": "kannada",
      "gender_needed": "female",
      "religion": "hindu",
      "created_at": "2026-08-03T10:00:00Z",
      "my_response": null
    }
  ]
}
```

**Notes:**
- `salary_range` is derived from work_type (static ranges).
- `my_response` is `null` if not yet responded, or `"accepted"` / `"rejected"` / `"more_details"`.

---

#### POST `/caregiver/jobs/:id/respond`

Respond to a job posting. Caregiver can respond multiple times (update their response — e.g., ask for details first, then accept/reject later).

**Request:**
```json
{
  "response": "more_details",
  "message": "What are the patient's mobility limitations?"
}
```

**Validation:**
- `response`: Required, must be one of: `accepted`, `rejected`, `more_details`.
- `message`: Required if response is `more_details` (the question for admin). Optional otherwise.
- Job must be `active` (cannot respond to closed jobs).
- Caregiver must have status `available` or `assigned` to respond. `unavailable` caregivers cannot respond (they must toggle back to `available` first). Others get error JOB_001.
- If caregiver already responded, their response is updated (not duplicated).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Response recorded",
    "response": "accepted"
  }
}
```

---

### 6.7 Super Admin Endpoints

#### POST `/admin/users`

Create a new admin account.

**Request:**
```json
{
  "email": "newadmin@vitacasahealth.in",
  "phone": "+919999999999",
  "full_name": "Admin User",
  "password": "securepassword"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "email": "newadmin@vitacasahealth.in",
    "role": "admin"
  }
}
```

---

#### GET `/admin/users`

List all admin accounts.

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "user_id": "uuid",
      "email": "admin1@vitacasahealth.in",
      "phone": "+919999999999",
      "full_name": "Admin One",
      "role": "admin",
      "is_active": true,
      "created_at": "2026-08-01T10:00:00Z"
    }
  ]
}
```

---

#### PUT `/admin/users/:id`

Update admin account details.

---

#### DELETE `/admin/users/:id`

Deactivate admin account (soft delete — sets `is_active = false`).

**DO NOT** actually delete the row. Only set `is_active = false`.

---

### 6.8 Audit Log Endpoints

#### GET `/admin/audit-logs`

**Query Parameters:**
- `page`, `limit`, `sort`, `order` (standard pagination)
- `user_id` (filter by who performed the action)
- `target_user_id` (filter by who was affected)
- `action` (filter by action type)
- `from_date`, `to_date` (filter by date range)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "user_name": "Admin One",
      "target_user_id": "uuid",
      "target_user_name": "Ramesh Kumar",
      "action": "status_changed",
      "entity_type": "caregiver_profiles",
      "entity_id": "uuid",
      "before_value": { "verification_status": "pending_verification" },
      "after_value": { "verification_status": "available" },
      "ip_address": "192.168.1.1",
      "created_at": "2026-08-01T14:30:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 100, "totalPages": 5 }
}
```

**DO NOT:**
- Do NOT allow caregivers to access audit logs.
- Do NOT provide CSV/Excel export functionality in V1.

---

## 7. Error Catalog

### 7.1 Authentication Errors (AUTH_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| AUTH_001 | 409 | Phone number is already registered | Registration with existing phone |
| AUTH_002 | 404 | No account found with this phone number | Login with unregistered phone |
| AUTH_003 | 401 | Invalid email or password | Admin email login with wrong credentials |
| AUTH_004 | 401 | Account is deactivated | Login to deactivated account |
| AUTH_005 | 401 | Invalid or expired token | Expired/malformed JWT |
| AUTH_006 | 401 | Invalid refresh token | Expired/invalid refresh token |
| AUTH_007 | 403 | Insufficient permissions | Accessing endpoint without required role |
| AUTH_008 | 401 | Invalid code | Phone+code login with wrong 4-digit code |

### 7.2 Profile Errors (PROFILE_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| PROFILE_001 | 400 | Full name is required | Missing full_name |
| PROFILE_003 | 400 | Invalid gender value | Gender not in enum |
| PROFILE_004 | 400 | Age must be between 18 and 65 | Age out of range |
| PROFILE_005 | 400 | At least one language is required | Empty languages array |
| PROFILE_006 | 400 | Invalid language value: {value} | Language not in enum |
| PROFILE_007 | 400 | Invalid phone number format | Phone doesn't match pattern |
| PROFILE_008 | 403 | Advanced details not available. Phone call verification required. | Trying to submit advanced details before call_verified |
| PROFILE_009 | 400 | Terms and conditions must be accepted | terms_accepted is false |
| PROFILE_010 | 400 | Invalid religion value | Religion not in enum |
| PROFILE_011 | 400 | Father's name is required | Missing father_name in advanced details |
| PROFILE_012 | 400 | At least one service mode is required | Empty service_modes array |
| PROFILE_013 | 400 | Invalid service mode: {value} | Service mode not in enum |
| PROFILE_014 | 400 | Current address is required | Missing current_address |
| PROFILE_015 | 400 | Address must be under 500 characters | Address too long |
| PROFILE_016 | 400 | Code must be exactly 4 digits | Code not matching /^\d{4}$/ |
| PROFILE_017 | 400 | Aadhaar card not uploaded. Please upload it before submitting. | Advanced submit without Aadhaar |
| PROFILE_018 | 400 | Invalid qualification value | Qualification not in allowed list |
| PROFILE_019 | 404 | Caregiver profile not found | Profile ID doesn't exist |
| PROFILE_020 | 400 | Name must contain only alphabetic characters and spaces | Invalid characters in name |
| PROFILE_021 | 400 | FCM token is required | Empty/missing token on `PUT /caregiver/fcm-token` |

### 7.3 Upload Errors (UPLOAD_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| UPLOAD_001 | 400 | File is required | No file in request |
| UPLOAD_002 | 400 | File size exceeds 10MB limit | File > 10MB |
| UPLOAD_003 | 400 | Maximum 3 additional documents allowed | Trying to upload 4th "other" doc |
| UPLOAD_004 | 400 | Invalid document_type. Must be: qualification, aadhaar, or other | Bad document_type value |
| UPLOAD_005 | 500 | File upload failed. Please try again. | Supabase Storage error |

### 7.4 Admin Errors (ADMIN_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| ADMIN_001 | 400 | Invalid status transition from {current} to {requested} | Invalid status change |
| ADMIN_002 | 400 | Cannot mark as call verified. Current status is not pending_call. | Call verify on wrong status |
| ADMIN_003 | 409 | Admin with this email already exists | Creating duplicate admin |
| ADMIN_004 | 404 | Admin user not found | Invalid admin user ID |
| ADMIN_005 | 400 | Cannot deactivate your own account | Self-deactivation attempt |
| ADMIN_006 | 400 | Cannot deactivate a super admin | Trying to deactivate super_admin |
| ADMIN_007 | 400 | Rejection message must be under 1000 characters | Rejection message too long |
| ADMIN_008 | 400 | Invalid code format. Must be exactly 4 digits. | Admin changing code with invalid format |
| ADMIN_009 | 409 | This phone number is already registered to another account | Phone change to existing number |
| ADMIN_010 | 400 | Invalid phone number format | Phone doesn't match +91 pattern |
| ADMIN_011 | 400 | No pending edits to acknowledge | Acknowledge when has_pending_edits is false |

### 7.5 Job Errors (JOB_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| JOB_001 | 403 | Cannot respond to jobs until your profile is verified | Non-available/assigned caregiver trying to respond |
| JOB_002 | 400 | Job is closed and no longer accepting responses | Responding to a closed job |
| JOB_003 | 400 | Message is required when asking for more details | response=more_details without message |
| JOB_004 | 400 | Invalid response value | response not in enum |

### 7.6 General Errors (GEN_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| GEN_001 | 400 | Invalid request body | Malformed JSON |
| GEN_002 | 404 | Resource not found | Generic 404 |
| GEN_003 | 500 | Internal server error | Unhandled exception |
| GEN_004 | 429 | Too many requests | Rate limit hit (future) |
| GEN_005 | 400 | Invalid pagination parameters | Bad page/limit values |

---

## 8. Push Notifications

### 8.1 Backend (NestJS)

**Integration:** Firebase Admin SDK.

**FCM Token Management:**
- Caregiver app sends FCM token to backend after registration and on each app launch.
- Token stored in `users.fcm_token` column.
- Endpoint: `PUT /caregiver/fcm-token` with body `{ "token": "fcm_token_string" }`.

**Notification Events:**

| Event | Recipient | Title | Body |
|-------|-----------|-------|------|
| Call Verified | Caregiver | Phone Verified | Your phone has been verified. Please fill your details to proceed. |
| Status: Available | Caregiver | Profile Approved | Congratulations! Your profile has been verified. You are now available for work assignments. |
| Status: Rejected | Caregiver | Profile Update Required | Your profile needs updates. Please check the app for details. |
| Status: In Process | Caregiver | Profile Under Review | Your documents are being reviewed. We'll update you soon. |
| New Job Posted | All Caregivers | New Job: {work_type_display} - ₹{min}–₹{max} | {city} \| {duty_timings_display} \| IMMEDIATELY APPLY |
| Daily Availability Reminder | Verified caregivers (available/unavailable) | Update Your Availability | Are you available for work today? Open app to confirm. |

**Payload Structure:**
```json
{
  "notification": {
    "title": "Phone Verified",
    "body": "Your phone has been verified. Please fill your details to proceed."
  },
  "data": {
    "type": "status_change",
    "status": "call_verified",
    "profile_id": "uuid"
  }
}
```

### 8.2 Flutter Client (Caregiver App)

**Setup:**
- Initialize Firebase in `main.dart`.
- Request notification permission on first launch.
- Obtain FCM token and send to backend.
- Listen for token refresh and update backend.

**Handling Scenarios:**

| App State | Behavior |
|-----------|----------|
| Foreground | Show in-app banner/snackbar with notification content. Do NOT show system notification. |
| Background | System notification shown automatically by FCM. |
| Terminated | System notification shown. App opens on tap. |

**Tap Navigation:**
- `type: "status_change"` + `status: "call_verified"` → Navigate to Advanced Details screen.
- `type: "status_change"` + `status: "available"` → Navigate to Home screen.
- `type: "status_change"` + `status: "rejected"` → Navigate to Profile screen (shows rejection message).
- `type: "status_change"` + `status: "in_process"` → Navigate to Verification Status screen.

**DO NOT:**
- Do NOT send push notifications to admins in V1 (admins use real-time dashboard).
- Do NOT send silent/data-only notifications — always include a visible notification.
- Do NOT request notification permission at registration. Request on first app launch after splash screen.

---

## 9. Real-Time Updates

### 9.1 Admin Dashboard — Supabase Realtime

The admin dashboard subscribes to Supabase Realtime for live updates.

**Authentication for Realtime:** Since we're not using Supabase Auth, the admin dashboard connects to Supabase Realtime using the Supabase **anon key**. RLS (Row Level Security) is disabled on the tables the admin subscribes to — access control is handled by the NestJS API layer, not at the database level.

**Alternative:** If RLS must be enabled, use a custom JWT that Supabase can verify (configure Supabase JWT secret to match our `JWT_SECRET`). This allows Supabase Realtime to accept our custom JWTs.

**Subscriptions:**

| Channel | Table | Events | Purpose |
|---------|-------|--------|---------|
| `caregiver_profiles` | `caregiver_profiles` | INSERT, UPDATE | New registrations, status changes |
| `admin_notes` | `admin_notes` | INSERT, UPDATE | Notes updated by another admin |

**Implementation (Flutter Web):**

```dart
// Pseudocode — connect with anon key (RLS disabled on these tables)
final supabase = Supabase.instance.client;

supabase.channel('admin-dashboard')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'caregiver_profiles',
    callback: (payload) => refreshDashboardStats(),
  )
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'caregiver_profiles',
    callback: (payload) => updateCaregiverInList(payload),
  )
  .subscribe();
```

**Behavior:**
- Dashboard stats cards update automatically when a new caregiver registers or status changes.
- Caregiver list updates in real-time (new row appears, status badge changes).
- If admin is viewing a caregiver detail and another admin changes the status, show a toast: "This profile was updated by another admin. Refreshing..."

**DO NOT:**
- Do NOT use Supabase Realtime in the caregiver mobile app. Caregivers use push notifications.
- Do NOT subscribe to `audit_logs` table in realtime (too noisy, unnecessary).
- Do NOT expose the Supabase service role key in the admin web app. Use only the anon key.
- Do NOT rely on Supabase Realtime as the sole source of data — always verify against the NestJS API. Realtime is for live UI updates, not authoritative data.

---

## 10. Email Notifications

### 10.1 Provider & Configuration

- **Provider:** Nodemailer with Gmail SMTP
- **Format:** Plain text (no HTML templates in V1)
- **From address:** `vitacasahealthindia@gmail.com`
- **Admin notification recipient:** `vitacasahealthindia@gmail.com` (single address for all admin notifications in V1. Per-admin routing is not supported.)
- **Daily send limit:** ~500 emails/day (Gmail SMTP limit)
- **Authentication:** Gmail App Password (2FA must be enabled on the Gmail account)

**Gmail SMTP Settings:**
```
Host: smtp.gmail.com
Port: 587
Secure: false (STARTTLS)
Auth: vitacasahealthindia@gmail.com + App Password
```

### 10.2 Email Templates

#### New Registration (to Admin)

```
Subject: New Caregiver Registration - {full_name}

A new caregiver has registered on VitaCare.

Name: {full_name}
Phone: {phone}
Gender: {gender}
Age: {age}
Languages: {languages_comma_separated}

Status: Pending Call

Please call to verify their phone number.

---
VitaCare Admin
```

#### Advanced Details Submitted (to Admin)

```
Subject: Profile Submitted for Review - {full_name}

Caregiver {full_name} has submitted their profile for verification.

Phone: {phone}
Qualification: {highest_qualification}
Service Modes: {service_modes_comma_separated}

Please review their documents in the admin dashboard.

---
VitaCare Admin
```

#### Profile Updated (to Admin)

```
Subject: Caregiver Profile Updated - {full_name}

Caregiver {full_name} has updated their profile.

Changed fields:
{field_name}: {old_value} → {new_value}
{field_name}: {old_value} → {new_value}

Their profile has been flagged for review. Current verification status remains unchanged.

---
VitaCare Admin
```

**DO NOT:**
- Do NOT use HTML emails in V1. Plain text only.
- Do NOT exceed 500 emails/day (Gmail SMTP limit). For V1 scale (<500 caregivers) this is sufficient.
- Do NOT use the Gmail account password directly. Use a Gmail App Password with 2FA enabled.

---

## 11. Audit Logging

### 11.1 Implementation

Implemented as a NestJS interceptor that wraps every mutating request.

**Interceptor Logic:**
1. Before handler: Capture `before_value` by reading current state.
2. After handler: Capture `after_value` from the response/new state.
3. Write audit log entry.

**What gets logged:**

| Action | entity_type | Captured Values |
|--------|-------------|-----------------|
| `registration` | `users` | after: new user data |
| `login` | `users` | after: { timestamp, method } |
| `call_verified` | `caregiver_profiles` | before/after: status change |
| `advanced_details_submitted` | `caregiver_profiles` | after: submitted fields |
| `profile_updated` | `caregiver_profiles` | before/after: changed fields only |
| `status_changed` | `caregiver_profiles` | before/after: status + who changed it |
| `code_changed` | `users` | after: { timestamp, changed_by } |
| `service_mode_assigned` | `caregiver_service_modes` | before/after: modes list |
| `admin_edit_profile` | `caregiver_profiles` | before/after: changed fields |
| `admin_note_added` | `admin_notes` | before/after: note content |
| `admin_created` | `users` | after: new admin data |
| `admin_deactivated` | `users` | before/after: is_active change |
| `phone_changed` | `users` | before/after: phone number values |
| `edits_acknowledged` | `caregiver_profiles` | after: { has_pending_edits: false } |

### 11.2 Rules

- Audit logs are append-only. Never update or delete audit log entries.
- `before_value` and `after_value` contain only the changed fields, not the entire record.
- `ip_address` is extracted from the request headers (`x-forwarded-for` or `req.ip`).
- `user_id` is the person performing the action (from JWT).
- `target_user_id` is the person being affected (if different from actor).

**DO NOT:**
- Do NOT log GET requests (reads).
- Do NOT log failed login attempts in V1 (future enhancement).
- Do NOT store passwords or tokens in audit log values.
- Do NOT provide export/download functionality for audit logs in V1.

---

## 12. Mobile App — Screens & Navigation

### 12.1 Screen List

| # | Screen Name | Route | Access Condition |
|---|-------------|-------|-----------------|
| 1 | Splash | `/` | Always (app launch) |
| 2 | Login | `/login` | Unauthenticated |
| 3 | Registration | `/register` | Unauthenticated |
| 4 | Pending Call | `/pending-call` | Authenticated, status = pending_call |
| 5 | Advanced Details Form (incl. document upload) | `/advanced-details` | Authenticated, status = call_verified |
| 7 | Verification Status | `/verification-status` | Authenticated, status = pending_verification or in_process |
| 8 | Rejection Details | `/rejection` | Authenticated, status = rejected |
| 9 | Home | `/home` | Authenticated, status = available/assigned |
| 9a | Jobs Dashboard | `/jobs` | Authenticated, any status (view jobs; respond only if available/assigned) |
| 10 | Profile View | `/profile` | Authenticated, any status |
| 11 | Edit Basic Profile | `/profile/edit-basic` | Authenticated, any status |
| 12 | Edit Advanced Profile | `/profile/edit-advanced` | Authenticated, advanced_details_completed = true |
| 14 | Settings | `/settings` | Authenticated |

### 12.2 Navigation Flow

```
App Launch → Splash
  ├── No token → Login
  │     ├── "Register" tap → Registration
  │     └── Successful login → Route by status (see below)
  └── Has valid token → Route by status

Route by verification_status:
  ├── pending_call → Pending Call screen
  ├── call_verified → Advanced Details Form (documents uploaded inline on this same screen)
  ├── pending_verification → Verification Status
  ├── in_process → Verification Status
  ├── rejected → Rejection Details
  │     └── "Edit & Resubmit" → Edit Advanced Profile
  ├── available → Home
  └── assigned → Home
```

### 12.3 Screen Details

#### Splash (`/`)
- Show app logo for 1-2 seconds.
- Check for stored JWT token.
- If token exists, validate (refresh if expired).
- Navigate based on auth state.

#### Login (`/login`)
- Phone number input field (with +91 prefix).
- 4-digit code input (always shown — every caregiver sets a code at registration).
- "Login" button.
- "New here? Register" link at bottom.
- After successful login, route by `verification_status`.

#### Registration (`/register`)
- **Salary ranges display** (informational, to attract caregivers):
  - Companion Care: ₹25,000 – ₹30,000
  - Bedside Care: ₹28,000 – ₹35,000
  - Critical Care: ₹30,000 – ₹45,000
- Fields: Full Name, Phone (+91), Gender (dropdown), Age (number input), Languages (multi-select chips), 4-Digit Login Code (numeric PIN input, obscured) — this is the code the caregiver will use with their phone number to log in from here on.
- "Take Selfie" button → opens camera (NOT gallery). Use Flutter `ImagePicker` with `source: ImageSource.camera`. Do NOT offer `ImageSource.gallery` option. No server-side EXIF validation — this is client-side enforcement only.
- "Register" button.
- On success → navigate to Pending Call screen.

#### Pending Call (`/pending-call`)
- Display message: "Thank you for registering! You will receive a call from our office shortly to verify your phone number."
- Show caregiver's registered name and phone.
- No action buttons. This is a waiting screen.
- Pull-to-refresh to check if status has changed.

#### Advanced Details Form (`/advanced-details`)
- Mandatory fields (Highest Qualification, Religion, Aadhaar upload, Terms & Conditions) are shown first and explicitly labeled "(mandatory)"; optional fields follow. Fields: Highest Qualification (dropdown, mandatory), Religion (dropdown: Hindu, Muslim, Christian, Others, mandatory), Current Address (text area, optional), Father's Name (text, optional), Father's Phone (+91, optional), Preferred City (multi-select chips: Bangalore, Mumbai, etc., optional), Notes (text area, optional), Terms & Conditions (checkbox with link, mandatory). No code field here — the login code was already set at registration.
- Document upload is inline on this same screen (no separate page/navigation):
  - Aadhaar Card (mandatory): upload button + status indicator.
  - Qualification Document (optional): upload button + status indicator.
  - Other Documents (optional): up to 3 upload slots.
  - Each upload shows a progress indicator and updates in place.
- "Submit" button (disabled until Aadhaar is uploaded and all other required fields are filled — qualification/other documents are not required).

#### Verification Status (`/verification-status`)
- Show current status with visual indicator (timeline/stepper).
- Status message: "Your profile is under review. We'll notify you once verified."
- Pull-to-refresh.

#### Rejection Details (`/rejection`)
- Show rejection message from admin (if provided).
- "Edit & Resubmit" button → navigates to Edit Advanced Profile.

#### Home (`/home`)
- Welcome message with caregiver's name.
- **Green verified icon** displayed prominently (indicates verified status).
- Quick stats/info:
  - Status badge (Available / Assigned) with green icon for verified.
  - Assigned work types and salary (read-only, admin-set).
  - Service modes (read-only, admin-set).
- Jobs section: List of active job postings with Accept / Reject / Ask More Details buttons.
- Navigation to: Profile, Jobs, Settings.

#### Jobs Dashboard (`/jobs`)
- List of all active job postings.
- Each job card shows: Work Type (with salary range), City, Duty Timings, Language, Gender, Religion, Description.
- Action buttons per job: **Accept**, **Reject**, **Ask for More Details**.
- Already-responded jobs show the response status (greyed out actions).
- Pull-to-refresh for new jobs.

#### Profile View (`/profile`)
- Display all profile information (read-only).
- "Edit" button.

#### Edit Basic Profile (`/profile/edit-basic`)
- Editable: Age, Languages.
- Full Name and Gender shown read-only — contact the office to change either; only admins can.
- "Save" button.
- Info banner: "Changes will be reviewed by admin. Your current verification status is not affected."

#### Edit Advanced Profile (`/profile/edit-advanced`)
- Editable: Qualification, Address, Preferred City, Notes.
- Religion shown read-only — contact the office to change it; only admins can (it's still settable on the Advanced Details form itself, during initial submission or rejected-resubmission — just not here).
- Document re-upload buttons.
- Service Modes, Work Types, Salary displayed as read-only (admin-assigned).
- "Save" button.
- Info banner: "Changes will be reviewed by admin. Your current verification status is not affected."

#### Settings (`/settings`)
- Change code (4-digit PIN update).
- Logout button.
- App version.

### 12.4 Navigation Rules

**DO NOT:**
- Do NOT allow navigation to Advanced Details if status is not `call_verified`.
- Show bottom navigation bar at all times after registration (including pending statuses). Seeing jobs motivates caregivers to complete onboarding.
- Do NOT allow back navigation from Pending Call to Registration (registration is complete).
- Do NOT show "Edit Advanced Profile" if `advanced_details_completed` is false.

---

## 13. Admin Dashboard — Screens & Navigation

### 13.1 Screen List

| # | Screen Name | Route | Access |
|---|-------------|-------|--------|
| 1 | Login | `/login` | Public |
| 2 | Dashboard | `/dashboard` | Admin, Super Admin |
| 3 | Caregiver List | `/caregivers` | Admin, Super Admin |
| 4 | Caregiver Detail | `/caregivers/:id` | Admin, Super Admin |
| 5 | Audit Logs | `/audit-logs` | Admin, Super Admin |
| 6 | Admin Management | `/admins` | Super Admin only |
| 7 | Settings | `/settings` | Admin, Super Admin |

### 13.2 Navigation Structure

**Sidebar Navigation:**
- Dashboard (icon: grid)
- Caregivers (icon: people)
- Audit Logs (icon: clipboard)
- Admin Management (icon: shield) — only visible to Super Admin
- Settings (icon: gear)

### 13.3 Screen Details

#### Dashboard (`/dashboard`)
- Stats cards (real-time updated):
  - Total Caregivers
  - Pending Call
  - Call Verified
  - Pending Verification
  - In Process
  - Verified
  - Rejected
  - New (24h)
  - New (7d)
- "Pending Edits" card shows count of verified caregivers who have edited their profile (needs review).
- Cards are clickable → navigate to Caregiver List with that status pre-filtered.

#### Caregiver List (`/caregivers`)
- Sortable data table.
- Columns: Name, Phone, Gender, Age, Qualification, Service Modes, Status, Registered.
- Filter panel (collapsible):
  - Search (text)
  - Status (dropdown)
  - Qualification (dropdown)
  - Language (multi-select)
  - Service Mode (dropdown)
  - Date range (from/to pickers)
- Quick filter chips: Last 24h, Last 7d, Last 30d.
- Click row → navigate to Caregiver Detail.
- Real-time: new rows appear automatically, status badges update live.

#### Caregiver Detail (`/caregivers/:id`)
- **Header:** Name, phone, status badge, registration date.
- **Tabs:**
  - Profile: All profile fields displayed.
  - Documents: Inline preview (image viewer / PDF viewer). Download button.
  - Notes: Admin notes form (internal notes, rates per mode, remarks). Save button.
  - Audit History: Filtered audit log for this caregiver.
- **Action buttons (based on status):**
  - `pending_call` → "Mark Call Verified" button.
  - `pending_verification` → "Start Review" (→ in_process), "Approve", "Reject" buttons.
  - `in_process` → "Approve", "Reject" buttons.
  - `verified` → No status actions.
  - `rejected` → No status actions (caregiver must re-submit).
- **Reject modal:** Text input for rejection message (optional), Confirm button.
- **Change Phone button:** Opens modal with new phone number input. For account recovery.

#### Audit Logs (`/audit-logs`)
- Data table: Timestamp, Actor, Target, Action, Changes.
- Filters: Action type, actor, target, date range.
- Expandable rows to show before/after JSON values.
- No export functionality.

#### Admin Management (`/admins`) — Super Admin only
- List of admin accounts (name, email, status).
- "Create Admin" button → modal form.
- Deactivate button per admin (with confirmation).

**DO NOT:**
- Do NOT show Admin Management to non-super-admin users.
- Do NOT allow inline editing of caregiver profiles directly from the list view — require navigating to detail.
- Do NOT show caregiver passwords or auth tokens anywhere in the dashboard.

---

## 14. Offline Support

### 14.1 Scope

Basic offline support: cache data for viewing, require internet for all writes.

### 14.2 Implementation

| Data | Cached | Method |
|------|--------|--------|
| Own profile | Yes | Hive/SharedPreferences |
| Verification status | Yes | Hive/SharedPreferences |
| Job postings | Yes | Hive/SharedPreferences |
| Uploaded document thumbnails | Yes | Image cache |

### 14.3 Behavior

- On app launch: attempt to fetch fresh data. If offline, show cached data with "Offline" banner at top.
- All mutating actions (profile update, document upload, availability save) require internet.
- If user attempts a write while offline, show error: "You are offline. Please check your internet connection and try again."
- When connectivity returns, auto-refresh current screen data.

**DO NOT:**
- Do NOT queue writes for later sync. All writes are online-only.
- Do NOT cache admin dashboard data (admins are expected to have connectivity).
- Do NOT implement a full offline-first architecture. This is view-only caching.

---

## 15. Constraints & Explicit Rules

### 15.1 What NOT to Build in V1

- **No OTP verification** — phone is verified by office call.
- **No family/patient features** — separate app in V2.
- **No booking/assignment system** — V2.
- **No payment processing** — V2.
- **No in-app messaging** — V2.
- **No AI matching** — V2+.
- **No rate limiting** — future enhancement.
- **No HTML emails** — plain text only.
- **No audit log export** — view only in dashboard.
- **No liveness detection for selfie** — basic camera capture only.
- **No video KYC** — documents + office call only.
- **No multi-tenancy** — single organization.
- **No localization/i18n** — English UI only in V1.
- **No dark mode** — single theme.
- **No analytics/reporting dashboards** — V3.
- **No caregiver-to-caregiver communication**.
- **No automated status transitions** — all status changes are manual (by admin or caregiver action).
- **One scheduled task only:** Daily push notification (8 AM) to verified caregivers (status = `available` or `unavailable`) reminding them to update availability. NOT sent to `assigned` caregivers (they're working). If caregiver does not respond, previous status stays unchanged. Notification shows two action buttons: "Available" and "Unavailable" — tapping either calls `PATCH /caregiver/availability-status`.

### 15.2 Security Rules

- All API endpoints (except `/auth/*` public routes) require valid JWT.
- Signed URLs for documents expire after 1 hour.
- Passwords: minimum 6 characters, no complexity rules in V1.
- Aadhaar data: NEVER store the Aadhaar number as text. Only store the document file path.
- Admin notes and rates: NEVER expose to caregiver-facing endpoints.
- Soft-delete for admin deactivation (never hard delete users).
- Never return more than 100 items per page (enforce max `limit`).

### 15.3 Data Validation Summary

| Field | Validation |
|-------|-----------|
| Phone | `/^\+91[6-9]\d{9}$/` |
| Email | Standard email regex, unique |
| Full Name | 1-100 chars, alphabetic + spaces |
| Age | Integer, 18-65 |
| Gender | Enum: male, female, other |
| Languages | Array, min 1, valid enum values |
| Service Modes | Array, min 1, valid enum values |
| Address | Max 500 chars |
| Code | Exactly 4 digits, numeric |
| File size | Max 10MB |
| Other documents | Max 3 files |
| Rejection message | Max 1000 chars |
| Preferred City | Valid city enum value |
| Availability notes | Max 500 chars |

### 15.4 Status Transition Matrix

```
pending_call ──────────────→ call_verified (admin action: call-verified endpoint)
call_verified ─────────────→ pending_verification (caregiver: submit advanced details)
pending_verification ──────→ in_process (admin: status endpoint)
pending_verification ──────→ available (admin: approve — sets verified_at, green icon)
pending_verification ──────→ rejected (admin: status endpoint)
in_process ────────────────→ available (admin: approve — sets verified_at, green icon)
in_process ────────────────→ rejected (admin: status endpoint)
available ─────────────────→ unavailable (caregiver OR admin: "not taking work right now")
unavailable ───────────────→ available (caregiver OR admin: "ready for work again")
available ─────────────────→ assigned (admin: assign endpoint — only from available, NOT unavailable)
assigned ──────────────────→ available (admin: unassign endpoint — work completed)
available ─────────────────→ pending_verification (admin: manual reset for re-review)
unavailable ───────────────→ pending_verification (admin: manual reset for re-review)
rejected ──────────────────→ pending_verification (caregiver: re-submit, no new call needed)
```

**No other transitions are allowed.**

### 15.5 Naming Conventions

| Context | Convention | Example |
|---------|-----------|---------|
| Database tables | snake_case | `caregiver_profiles` |
| Database columns | snake_case | `verification_status` |
| API endpoints | kebab-case | `/admin/caregivers/:id/call-verified` |
| API request/response fields | snake_case | `full_name`, `verification_status` |
| NestJS files | kebab-case | `caregiver.controller.ts` |
| NestJS classes | PascalCase | `CaregiverController` |
| Flutter files | snake_case | `caregiver_profile_screen.dart` |
| Flutter classes | PascalCase | `CaregiverProfileScreen` |
| Flutter routes | kebab-case | `/advanced-details` |
| Enums (DB) | snake_case | `pending_call`, `24hrs_live_in` |
| Error codes | UPPER_SNAKE | `AUTH_001`, `PROFILE_005` |

### 15.6 Performance Targets

| Metric | Target |
|--------|--------|
| API response (p95) | < 500ms |
| File upload (10MB) | < 10s on 4G |
| App cold start | < 3s |
| Profile load (cached) | < 100ms |
| Profile load (network) | < 2s |
| Dashboard initial load | < 3s |
| Real-time update latency | < 2s |

### 15.7 Environment Variables (API)

```env
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Database (if connecting directly)
DATABASE_URL=

# Email (Gmail SMTP via Nodemailer)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=vitacasahealthindia@gmail.com
SMTP_PASSWORD=                          # Gmail App Password (NOT the account password)

# Firebase
FIREBASE_PROJECT_ID=
FIREBASE_PRIVATE_KEY=
FIREBASE_CLIENT_EMAIL=

# App
API_PORT=3000
NODE_ENV=development
ADMIN_NOTIFICATION_EMAIL=vitacasahealthindia@gmail.com

# JWT (custom auth for caregivers and admins)
JWT_SECRET=                             # Random 256-bit secret for signing JWTs
JWT_ACCESS_TOKEN_TTL=15552000           # Admin web only — caregiver-app tokens never expire
JWT_REFRESH_TOKEN_TTL=2592000
```

**DO NOT:**
- Do NOT hardcode any of these values. Always use environment variables.
- Do NOT commit `.env` files to the repository.
- Do NOT use the Supabase service role key in client apps (Flutter). Only in the NestJS backend.
