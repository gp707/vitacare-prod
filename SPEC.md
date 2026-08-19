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
│  Caregiver App        │  │  NurseNow App          │  │  Admin Dashboard     │
│  ("NurseJobs")        │  │  (patient/family +     │  │  Flutter Web         │
│  Flutter Mobile       │  │   hospital/rehab)      │  │                      │
│  apps/caregiver-app   │  │  Flutter Mobile        │  │  apps/admin-web      │
│                       │  │  apps/nursenow-app     │  │                      │
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
  AVAILABLE: 'available',       // Verified & available for work (verified_at is set, green icon)
  UNAVAILABLE: 'unavailable',   // Verified but not available (caregiver or admin toggled off)
  ASSIGNED: 'assigned',         // Currently assigned to work
  REJECTED: 'rejected',
} as const;

export const JobStatus = {
  PENDING_REVIEW: 'pending_review',  // NurseNow individual posting awaiting admin approval
  ACTIVE: 'active',
  CLOSED: 'closed',
} as const;

export const JobApplicationStatus = {
  APPLIED: 'applied',
  REJECTED: 'rejected',
  ACCEPTED: 'accepted',
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

export const Religion = {
  HINDU: 'hindu',
  MUSLIM: 'muslim',
  CHRISTIAN: 'christian',
  OTHERS: 'others',
} as const;

export const DutyType = {
  DAY_DUTY: 'day_duty',
  NIGHT_DUTY: 'night_duty',
  LIVE_IN: 'live_in',
} as const;

export const FrequencyOfCare = {
  DAILY: 'daily',
  MONTHLY: 'monthly',
} as const;

export const Mobility = {
  WALKS_INDEPENDENTLY: 'walks_independently',
  WALKS_WITH_ASSISTANCE: 'walks_with_assistance',
  USES_WALKER: 'uses_walker',
  USES_WHEELCHAIR: 'uses_wheelchair',
  BEDRIDDEN: 'bedridden',
} as const;

export const Communication = {
  VERBAL: 'verbal',
  DIFFICULTY_COMMUNICATING: 'difficulty_communicating',
  SIGN_LANGUAGE: 'sign_language',
} as const;

export const FeedingType = {
  ORAL_INDEPENDENT: 'oral_independent',
  ORAL_NEEDS_ASSISTANCE: 'oral_needs_assistance',
  TUBE_FEEDING: 'tube_feeding',
  ORAL_AND_TUBE: 'oral_and_tube',
} as const;

export const MedicalAssistance = {
  MEDICATION_REMINDERS: 'medication_reminders',
  MEDICATION_ADMINISTRATION: 'medication_administration',
  INSULIN_ADMINISTRATION: 'insulin_administration',
  OTHER_INJECTIONS: 'other_injections',
  OTHER: 'other',
} as const;

export const MedicalCondition = {
  CANCER: 'cancer',
  STROKE: 'stroke',
  BRAIN_INJURY: 'brain_injury',
  DEMENTIA_ALZHEIMERS: 'dementia_alzheimers',
  PARKINSONS: 'parkinsons',
  HEART_CONDITION: 'heart_condition',
  KIDNEY_DISEASE_DIALYSIS: 'kidney_disease_dialysis',
  DIABETES: 'diabetes',
  COLOSTOMY: 'colostomy',
  PARALYSIS: 'paralysis',
  TB: 'tb',
  OTHER: 'other',
} as const;

export const ToiletAssistance = {
  USES_DIAPERS: 'uses_diapers',
  USES_BED_PAN: 'uses_bed_pan',
  USES_CATHETER: 'uses_catheter',
  COMPLETE_ASSISTANCE: 'complete_toileting_assistance',
  OTHERS: 'others',
  INDEPENDENT: 'independent',
} as const;

export const VitalMonitoringType = {
  BLOOD_PRESSURE: 'blood_pressure',
  BLOOD_SUGAR: 'blood_sugar',
  OXYGEN_SPO2: 'oxygen_spo2',
  TEMPERATURE: 'temperature',
  PULSE: 'pulse',
  OTHER: 'other',
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
  RN_ABOVE_2_YEARS: 'rn_above_2_years',
  RN_BELOW_2_YEARS: 'rn_below_2_years',
  REGISTERED_RECENTLY: 'registered_recently',
  BSC_GNM_UNREGISTERED: 'bsc_gnm_unregistered',
  ANM_STUDENT_BACKLOG: 'anm_student_backlog',
  GDA_NON_NURSING: 'gda_non_nursing',
} as const;

export const AuditAction = {
  REGISTRATION: 'registration',
  LOGIN: 'login',
  PROFILE_UPDATED: 'profile_updated',
  STATUS_CHANGED: 'status_changed',
  CODE_CHANGED: 'code_changed',
  ADMIN_EDIT_PROFILE: 'admin_edit_profile',
  ADMIN_NOTE_ADDED: 'admin_note_added',
  ADMIN_CREATED: 'admin_created',
  ADMIN_DEACTIVATED: 'admin_deactivated',
  PHONE_CHANGED: 'phone_changed',
  EDITS_ACKNOWLEDGED: 'edits_acknowledged',
  JOB_POSTED: 'job_posted',
  JOB_CLOSED: 'job_closed',
  JOB_RESPONSE: 'job_response',
  JOB_APPLICATION_DECIDED: 'job_application_decided',
  JOB_UPDATED: 'job_updated',
} as const;

export const UserRole = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  CAREGIVER: 'caregiver',
  INDIVIDUAL: 'individual',     // NurseNow patient/family account — see "NurseNow" in CLAUDE.md
  ORGANISATION: 'organisation', // NurseNow hospital/rehab/clinic account — see "NurseNow" in CLAUDE.md
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
  REJECTION_MESSAGE_MAX_LENGTH: 1000,
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
  static const available = 'available';       // Verified & available (green icon)
  static const unavailable = 'unavailable';   // Verified but not available (toggled off)
  static const assigned = 'assigned';         // Currently assigned to work
  static const rejected = 'rejected';

  static const all = [pendingCall, available, unavailable, assigned, rejected];
}

class JobStatus {
  static const pendingReview = 'pending_review';  // NurseNow individual posting awaiting admin approval
  static const active = 'active';
  static const closed = 'closed';

  static const all = [pendingReview, active, closed];
}
// organisation_requirements.status (NurseNow Organisation — hospital/rehab/clinic postings,
// see "NurseNow" in CLAUDE.md) reuses this exact same 3-value set independently — it is
// not a foreign key into jobs, just the same enum shape on a separate table.

class JobApplicationStatus {
  static const applied = 'applied';
  static const rejected = 'rejected';
  static const accepted = 'accepted';

  static const all = [applied, rejected, accepted];
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

class DutyType {
  static const dayDuty = 'day_duty';
  static const nightDuty = 'night_duty';
  static const liveIn = 'live_in';

  static const all = [liveIn, dayDuty, nightDuty];

  static const displayNames = {
    liveIn: '24Hrs - Live In',
    dayDuty: '12Hrs Day Shift (8am to 8pm)',
    nightDuty: '12Hrs Night Shift (8pm to 8am)',
  };
}

class FrequencyOfCare {
  static const daily = 'daily';
  static const monthly = 'monthly';

  static const all = [daily, monthly];

  static const displayNames = {
    daily: 'Daily',
    monthly: 'Monthly',
  };
}

class Mobility {
  static const walksIndependently = 'walks_independently';
  static const walksWithAssistance = 'walks_with_assistance';
  static const usesWalker = 'uses_walker';
  static const usesWheelchair = 'uses_wheelchair';
  static const bedridden = 'bedridden';

  static const all = [walksIndependently, walksWithAssistance, usesWalker, usesWheelchair, bedridden];
}

class Communication {
  static const verbal = 'verbal';
  static const difficultyCommunicating = 'difficulty_communicating';
  static const signLanguage = 'sign_language';

  static const all = [verbal, difficultyCommunicating, signLanguage];
}

class FeedingType {
  static const oralIndependent = 'oral_independent';
  static const oralNeedsAssistance = 'oral_needs_assistance';
  static const tubeFeeding = 'tube_feeding';
  static const oralAndTube = 'oral_and_tube';

  static const all = [oralIndependent, oralNeedsAssistance, tubeFeeding, oralAndTube];
}

class MedicalAssistance {
  static const medicationReminders = 'medication_reminders';
  static const medicationAdministration = 'medication_administration';
  static const insulinAdministration = 'insulin_administration';
  static const otherInjections = 'other_injections';
  static const other = 'other';

  static const all = [
    medicationReminders,
    medicationAdministration,
    insulinAdministration,
    otherInjections,
    other,
  ];
}

class MedicalCondition {
  static const cancer = 'cancer';
  static const stroke = 'stroke';
  static const brainInjury = 'brain_injury';
  static const dementiaAlzheimers = 'dementia_alzheimers';
  static const parkinsons = 'parkinsons';
  static const heartCondition = 'heart_condition';
  static const kidneyDiseaseDialysis = 'kidney_disease_dialysis';
  static const diabetes = 'diabetes';
  static const colostomy = 'colostomy';
  static const paralysis = 'paralysis';
  static const tb = 'tb';
  static const other = 'other';

  static const all = [
    cancer,
    stroke,
    brainInjury,
    dementiaAlzheimers,
    parkinsons,
    heartCondition,
    kidneyDiseaseDialysis,
    diabetes,
    colostomy,
    paralysis,
    tb,
    other,
  ];
}

class ToiletAssistance {
  static const usesDiapers = 'uses_diapers';
  static const usesBedPan = 'uses_bed_pan';
  static const usesCatheter = 'uses_catheter';
  static const completeAssistance = 'complete_toileting_assistance';
  static const others = 'others';
  static const independent = 'independent';

  static const all = [
    usesDiapers,
    usesBedPan,
    usesCatheter,
    completeAssistance,
    others,
    independent,
  ];
}

class VitalMonitoringType {
  static const bloodPressure = 'blood_pressure';
  static const bloodSugar = 'blood_sugar';
  static const oxygenSpo2 = 'oxygen_spo2';
  static const temperature = 'temperature';
  static const pulse = 'pulse';
  static const other = 'other';

  static const all = [bloodPressure, bloodSugar, oxygenSpo2, temperature, pulse, other];
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

#### Registration: Everything in One Step

- Caregiver registers with phone number, basic details (gender, age, languages, religion, highest qualification, terms acceptance), and a self-chosen 4-digit numeric code — all in one `POST /auth/register` call. There is no separate "Advanced Details" step; documents (selfie, Aadhaar — both mandatory; qualification document and up to 3 "other" documents — optional) are uploaded via their own endpoints immediately after, on the same Registration screen.
- Backend creates a row in `users` table; code is hashed (bcrypt) and stored in `code_hash` at creation.
- Backend generates and issues a custom JWT immediately.
- **Login (from registration onward):** Caregiver enters phone number + 4-digit code → backend looks up user in `users` table, verifies the code hash → issues JWT.
- **Security model:** The code is collected at registration so every caregiver login, from the very first session, is phone + code — there is no phone-only fallback to reason about.
- **Session persistence:** JWT stored locally on device. Caregiver stays logged in until token expires or they log out.
- Admin reviews the phone call and the full submitted profile (already complete) and approves or rejects directly from `pending_call` — there's no intermediate "call verified" or "in review" state to track separately.

**DO NOT:**
- Do NOT use Supabase Auth for any accounts (caregiver or admin).
- Do NOT implement OTP verification at registration or login.
- Do NOT reintroduce a phone-only login endpoint.
- Do NOT reintroduce a separate "Advanced Details" submission step — everything is collected at registration.

#### Phone uniqueness is per app bucket, not global (migration 045)

`users.phone` is **not** a plain `UNIQUE` column — the original global constraint (`users_phone_key`) was dropped and replaced with a Postgres expression unique index (`users_phone_app_bucket_key`) on `(phone, bucket)`, where `bucket` is computed as `'nursejobs'` for `role = 'caregiver'`, `'nursenow'` for `role IN ('individual', 'organisation')`, and `'admin'` otherwise. Effectively there are three independent buckets:

- **NurseJobs** — caregiver accounts only.
- **NurseNow** — individual and organisation accounts share one bucket (an account is one or the other, never both, at a given phone — but a phone can hold at most one NurseNow account total, whichever type).
- **Admin** — admin/super_admin accounts.

A single phone number can hold **one account per bucket simultaneously** — e.g. the same person can be a NurseJobs caregiver AND, separately, a NurseNow individual with the exact same phone number. These are two fully independent, unlinked `users` rows (separate ids, separate profile rows, separate login PINs, separate audit trails) that merely happen to share a phone number; no data is shared or merged between them, and neither app is aware the other account exists. Registering a second account **within the same bucket** (e.g. a second caregiver account on the same phone, or an organisation account when that phone already holds an individual account) still 409s with `AUTH_001`, exactly as before this change.

`UsersRepository.findByPhoneAndRoles(phone, roles)` is the single role-scoped lookup used everywhere a phone is checked — registration dedup (each registration endpoint passes its own bucket's role list), self-service phone-change dedup (`PATCH /caregiver|individual|organisation/profile/phone`), and admin phone-change dedup (`POST`/`PATCH /admin/users`). The old role-agnostic `findByPhone` was removed entirely once every call site was migrated.

`POST /auth/login/code` (6.3 below) is called identically by caregiver-app and nursenow-app, but since a phone can now match more than one row, the request gained a required `app` field so the backend knows which bucket to search: `'nursejobs'` (caregiver-app always sends this) or `'nursenow'` (nursenow-app always sends this — it doesn't know ahead of login whether the account is individual or organisation; that's still decoded from the JWT's `role` claim client-side after a successful login, unchanged). The bucket-scoped lookup runs *before* the 4-digit code is even compared, so login can never accidentally authenticate into the wrong bucket's account even if both accounts happen to share the same PIN.

#### Self-Edit and the Login Code

- Admin can change a caregiver's code at any time via `/admin/caregivers/:id` (admin edit) or the caregiver can change it themselves via `PATCH /caregiver/profile/code`.

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
  phone VARCHAR(20) NOT NULL,             -- NOT globally unique — see users_phone_app_bucket_key below (migration 045)
  password_hash VARCHAR(255),             -- NULL for caregivers, set for admins only
  code_hash VARCHAR(255),                 -- NULL for admins, set at registration for caregivers (4-digit numeric code)
  full_name VARCHAR(100) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('super_admin', 'admin', 'caregiver', 'individual', 'organisation')),  -- 'individual' = NurseNow patient/family account, 'organisation' = NurseNow hospital/rehab/clinic account (see NurseNow section)
  is_active BOOLEAN DEFAULT true,
  fcm_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_is_active ON users(is_active);

-- Phone is unique PER APP BUCKET, not globally (migration 045) — a phone
-- can hold one caregiver account, one individual/organisation account, and
-- one admin/super_admin account, all at once, as three independent,
-- unlinked accounts. See 3.1's "Phone uniqueness is per app bucket".
CREATE UNIQUE INDEX users_phone_app_bucket_key ON users (
  phone,
  (CASE
     WHEN role = 'caregiver' THEN 'nursejobs'
     WHEN role IN ('individual', 'organisation') THEN 'nursenow'
     ELSE 'admin'
   END)
);

-- ============================================
-- CAREGIVER PROFILES TABLE
-- ============================================
CREATE TABLE caregiver_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  caregiver_number INTEGER NOT NULL UNIQUE DEFAULT nextval('caregiver_profiles_caregiver_number_seq'),  -- human-friendly sequential id, starts at 500 (migration 046); displayed as "NUR-<n>"
  selfie_photo_url TEXT,
  gender VARCHAR(30) NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  age INTEGER NOT NULL CHECK (age >= 18 AND age <= 65),
  highest_qualification VARCHAR(100),
  qualification_document_url TEXT,
  aadhaar_document_url TEXT,
  religion VARCHAR(20) CHECK (religion IN ('hindu', 'muslim', 'christian', 'others')),  -- Set once at registration
  other_document_urls JSONB DEFAULT '[]',
  terms_accepted BOOLEAN DEFAULT false,
  verification_status VARCHAR(30) DEFAULT 'pending_call'
    CHECK (verification_status IN (
      'pending_call',
      'available',
      'unavailable',
      'assigned',
      'rejected'
    )),
  rejection_message TEXT,
  has_pending_edits BOOLEAN DEFAULT false,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users(id),      -- App validates this is admin/super_admin
  -- Job search preferences (with preferred_cities/preferred_duty_types,
  -- both in their own junction tables below) — dynamically filter
  -- GET /caregiver/jobs, editable anytime via the self-edit endpoint,
  -- never gate anything and never affect verification_status.
  min_salary_per_day INTEGER CHECK (min_salary_per_day > 0),
  min_salary_per_month INTEGER CHECK (min_salary_per_month > 0),
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
-- CAREGIVER PREFERRED DUTY TYPES TABLE
-- Job search preference (shift type): caregiver can select multiple
-- preferred duty types, same many-to-many pattern as
-- caregiver_preferred_cities / caregiver_languages. Dynamically filters
-- GET /caregiver/jobs — see caregiver_profiles.min_salary_per_day/
-- min_salary_per_month below, and "Caregiver job search preferences" in
-- CLAUDE.md.
-- ============================================
CREATE TABLE caregiver_preferred_duty_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  duty_type VARCHAR(20) NOT NULL CHECK (duty_type IN ('live_in', 'day_duty', 'night_duty')),
  UNIQUE(profile_id, duty_type)
);

CREATE INDEX idx_caregiver_preferred_duty_types_profile ON caregiver_preferred_duty_types(profile_id);

-- caregiver_profiles also carries min_salary_per_day and
-- min_salary_per_month (both nullable INTEGER, CHECK > 0) — see the
-- caregiver_profiles table definition above for the full column list.
-- Each is only ever compared against a job of the matching
-- frequency_of_care (a daily job's salary is never compared against
-- min_salary_per_month and vice versa).

-- Admin-assigned work types, service modes, and salary (formerly
-- caregiver_service_modes / caregiver_work_types tables + a caregiver_
-- profiles.salary column) have been removed from the product entirely.
-- WorkType/ServiceMode/SalaryRanges are gone too — a job posting is no
-- longer built around a single "work type" category (see the jobs/
-- care_receivers/job_applications tables below).

-- ============================================
-- ADMIN NOTES TABLE
-- ============================================
CREATE TABLE admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES users(id),
  internal_notes TEXT,
  availability_remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id)
);

-- ============================================
-- INDIVIDUAL PROFILES TABLE (NurseNow patient/family accounts — see
-- "NurseNow" in CLAUDE.md. Mirrors caregiver_profiles' role-specific-data
-- pattern, but no verification workflow — just the two admin block levers.)
-- ============================================
CREATE TABLE individual_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  patient_number INTEGER NOT NULL UNIQUE DEFAULT nextval('individual_profiles_patient_number_seq'),  -- human-friendly sequential id, starts at 500 (migration 046); displayed as "PAT-<n>"
  is_job_posting_blocked BOOLEAN NOT NULL DEFAULT false,  -- blocks new POST /individual/requirements only (JOB_010); existing live requirement/applications keep working
  block_reason TEXT,                      -- admin-entered, shown to the individual; also used for a full block (users.is_active = false)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Full block (can't log in at all) reuses users.is_active + AUTH_004 —
-- already wired into loginCode. No separate column needed for that state.

-- ============================================
-- CARE RECEIVERS TABLE (1:1 with a job — see "Job/Application Flow" in
-- CLAUDE.md. Not an independently reusable/searchable entity yet; a future
-- "Patient" app will eventually supply real care-receiver identity data.)
-- ============================================
CREATE TABLE care_receivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  age INTEGER NOT NULL CHECK (age BETWEEN 1 AND 120),
  gender VARCHAR(10) NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  weight_kg INTEGER NOT NULL CHECK (weight_kg BETWEEN 1 AND 300),
  mobility VARCHAR(30) NOT NULL CHECK (mobility IN (
    'walks_independently', 'walks_with_assistance', 'uses_walker', 'uses_wheelchair', 'bedridden'
  )),
  communication VARCHAR(30) NOT NULL CHECK (communication IN (
    'verbal', 'difficulty_communicating', 'sign_language'
  )),  -- "Can Speak/Communicate" / "Can NOT Speak" / "Communicate via Sign Languages"
  feeding_type VARCHAR(30) NOT NULL CHECK (feeding_type IN (
    'oral_independent', 'oral_needs_assistance', 'tube_feeding', 'oral_and_tube'
  )),
  medical_assistance JSONB NOT NULL DEFAULT '[]',
  has_medical_condition BOOLEAN NOT NULL DEFAULT false,
  medical_conditions JSONB NOT NULL DEFAULT '[]',  -- only populated when has_medical_condition
  medical_condition_other TEXT,           -- free text shown when medical_conditions includes 'other'
  toilet_assistance JSONB NOT NULL DEFAULT '[]',  -- multi-select: uses_diapers/uses_bed_pan/uses_catheter/complete_toileting_assistance/others/independent
  toilet_assistance_other TEXT,           -- free text shown when toilet_assistance includes 'others'
  requires_vital_monitoring BOOLEAN NOT NULL DEFAULT false,
  vital_monitoring_types JSONB NOT NULL DEFAULT '[]',  -- only populated when requires_vital_monitoring
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- JOBS TABLE (admin-posted job listings)
-- ============================================
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_number SERIAL UNIQUE,               -- internal only, no longer displayed (see admin_job_number/patient_job_number below); distinct from id (UUID)
  admin_job_number INTEGER UNIQUE,        -- set only for an admin-posted job; sequence starts at 500 (migration 047); shown as "ADMIN-JOB-<n>"
  patient_job_number INTEGER UNIQUE,      -- set only for a NurseNow individual-posted job; sequence starts at 500 (migration 047); shown as "PAT-JOB-<n>"
  care_receiver_id UUID NOT NULL REFERENCES care_receivers(id),
  city VARCHAR(30) NOT NULL CHECK (city IN ('bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon')),
  area TEXT,                              -- free text; required via API (DTO), nullable at DB level only for rows that predate this being required
  description TEXT,                       -- free text; optional via API — previously required, DB NOT NULL constraint dropped in migration 034
  duty_type VARCHAR(20) NOT NULL CHECK (duty_type IN ('day_duty', 'night_duty', 'live_in')),  -- 3 fixed shifts only; UI label "Hours Care Needed"
  frequency_of_care VARCHAR(10) CHECK (frequency_of_care IN ('daily', 'monthly')),  -- nullable: a NurseNow individual's pending_review posting is created without it, admin sets it on approval (see NurseNow section)
  start_time TIME,                        -- derived from duty_type, not admin-entered; NULL for live_in
  end_time TIME,
  start_date DATE,                        -- UI label "Preferred Start Date"; required via API (DTO) — previously optional, nullable at DB level only for rows that predate this being required
  languages JSONB NOT NULL DEFAULT '[]',  -- multi-select language preference, non-empty array
  salary_amount INTEGER CHECK (salary_amount > 0),  -- ₹/day or ₹/month per frequency_of_care; required via API for every create/edit, nullable at DB level only for rows that predate this field
  preferred_gender VARCHAR(10) CHECK (preferred_gender IN ('male', 'female')),        -- NULL = no preference
  preferred_religion VARCHAR(20) CHECK (preferred_religion IN ('hindu', 'muslim', 'christian')),  -- NULL = no preference; 'others' excluded (valid for a caregiver's own religion, not offered as a job preference)
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('pending_review', 'active', 'closed')),  -- pending_review: a NurseNow individual's posting awaiting admin approval; admin's own postings skip straight to active
  rejection_reason TEXT,                  -- set only when admin rejects a pending_review posting; NULL otherwise, including a normal close
  posted_by UUID NOT NULL REFERENCES users(id),  -- an admin OR a NurseNow individual (users.role = 'individual'); no role restriction at the DB level
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- effective "went live" time; drives the 3-day apply-by urgency window; starts = created_at, bumped to NOW() only on repost (edit of a closed job)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);
CREATE INDEX idx_jobs_care_receiver ON jobs(care_receiver_id);

-- ============================================
-- JOB APPLICATIONS TABLE (caregiver applications to jobs)
-- ============================================
CREATE TABLE job_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('applied', 'rejected', 'accepted')),
  decided_by UUID REFERENCES users(id),   -- admin who accepted/rejected; NULL while the caregiver's own action produced the current status
  applied_at TIMESTAMPTZ,                 -- set on a fresh 'applied' upsert; NULL if they declined without ever applying
  accepted_at TIMESTAMPTZ,                -- set only by an admin decide() to 'accepted'
  rejected_at TIMESTAMPTZ,                -- set by either a caregiver self-decline or an admin decide() to 'rejected' (including undoing a prior acceptance)
  decline_reason TEXT,                    -- optional on admin's own reject; mandatory (JOB_012) when a NurseNow individual rejects — see "NurseNow" in CLAUDE.md
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(job_id, profile_id)
);

CREATE INDEX idx_job_applications_job ON job_applications(job_id);
CREATE INDEX idx_job_applications_profile ON job_applications(profile_id);

-- ============================================
-- ORGANISATION PROFILES TABLE (NurseNow hospital/rehab/clinic accounts —
-- see "NurseNow" in CLAUDE.md. Mirrors individual_profiles' shape [no
-- verification pipeline, just the two admin block levers] plus the
-- registration-collected org identity/location fields. city/area here are
-- the org's own registered location, reused as every one of its
-- requirements' location — there is no per-requirement city/area. city is
-- validated at the DTO layer against the existing 7-city list plus
-- 'others' [ORGANISATION_CITY_OTHERS] — a separate org-scoped list, NOT an
-- extension of the shared City enum, which stays caregiver/job-scoped.)
-- ============================================
CREATE TABLE organisation_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  org_number INTEGER NOT NULL UNIQUE DEFAULT nextval('organisation_profiles_org_number_seq'),  -- human-friendly sequential id, starts at 500 (migration 046); displayed as "ORG-<n>"
  organisation_name VARCHAR(200) NOT NULL,
  contact_person_name VARCHAR(100) NOT NULL,
  organisation_type VARCHAR(20) NOT NULL CHECK (organisation_type IN ('hospital', 'rehab', 'clinic')),
  city VARCHAR(30) NOT NULL,               -- org-scoped list: the 7 shared cities + 'others'; not a DB CHECK against the shared City enum
  area TEXT NOT NULL,
  is_job_posting_blocked BOOLEAN NOT NULL DEFAULT false,  -- blocks new POST /organisation/requirements only (JOB_010); existing live requirements/applications keep working
  block_reason TEXT,                        -- admin-entered, shown to the org; also used for a full block (users.is_active = false)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Full block (can't log in at all) reuses users.is_active + AUTH_004, exactly like individual_profiles — no separate column needed.

-- ============================================
-- ORGANISATION REQUIREMENTS TABLE (an organisation's posted requirement —
-- deliberately NOT a jobs row, see "NurseNow" in CLAUDE.md: a fundamentally
-- different posting shape, no care_receiver, a "type of nurse" enum
-- instead of a qualification enum, accommodation/food/special-skills
-- fields, no city/area/duty_type [inherited from the posting org's own
-- organisation_profiles row]. Unlike an Individual's postings, there is
-- NO one-live-requirement limit — an org may have many simultaneous
-- pending_review/active requirements.)
-- ============================================
CREATE TABLE organisation_requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requirement_number SERIAL UNIQUE,        -- short sequential id, distinct from id (UUID); sequence rebased to start at 500 (migration 047), shown as "ORG-JOB-<n>"
  posted_by UUID NOT NULL REFERENCES users(id),  -- always users.role = 'organisation'
  type_of_nurse VARCHAR(40) NOT NULL,      -- validated at the DTO layer against a fixed 7-value list (TypeOfNurse), not a DB CHECK, so it can be adjusted without a migration; distinct from a caregiver's own Qualification
  frequency_of_care VARCHAR(10) CHECK (frequency_of_care IN ('daily', 'monthly')),  -- nullable: created null, admin sets it on approval — same null-until-approved pattern as jobs.frequency_of_care for an individual's posting
  salary_amount INTEGER CHECK (salary_amount > 0),  -- admin-set on approval
  schedule_type VARCHAR(20) CHECK (schedule_type IN ('date_range', 'specific_days')),  -- admin-set on approval; replaces the single "Preferred Start Date" field entirely for organisation requirements — admin picks exactly one mode
  start_date DATE,                          -- populated only when schedule_type = 'date_range'
  end_date DATE,                            -- populated only when schedule_type = 'date_range'; must not be before start_date (ORG_001)
  schedule_repeat VARCHAR(10) CHECK (schedule_repeat IN ('weekly', 'monthly')),  -- populated only when schedule_type = 'specific_days'; picks what specific_days' numbers mean
  specific_days INTEGER[],                  -- populated only when schedule_type = 'specific_days'; ISO weekday numbers 1-7 (Mon-Sun) if schedule_repeat='weekly' (ORG_002 if out of range), else day-of-month numbers 1-31 if 'monthly'
  accommodation_provided BOOLEAN NOT NULL,
  food_provided BOOLEAN NOT NULL,
  special_skills TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review', 'active', 'closed')),
  rejection_reason TEXT,                    -- set only when admin rejects a pending_review requirement; null otherwise, including a normal close
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- starts = created_at, bumped to NOW() only when admin approves-from-pending_review or reposts a closed requirement
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- migration 043_organisation_requirement_schedule.sql added schedule_type/end_date/specific_days
-- migration 044_organisation_requirement_schedule_repeat.sql added schedule_repeat

CREATE INDEX idx_organisation_requirements_status ON organisation_requirements(status);
CREATE INDEX idx_organisation_requirements_posted_by ON organisation_requirements(posted_by);

-- ============================================
-- ORGANISATION REQUIREMENT APPLICATIONS TABLE (caregiver applications to
-- an organisation requirement — a separate table from job_applications,
-- same reasoning as organisation_requirements itself, but shaped
-- identically, including 'completed' status and decline_reason from day
-- one [job_applications only grew those in migrations 035/040].)
-- ============================================
CREATE TABLE organisation_requirement_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requirement_id UUID NOT NULL REFERENCES organisation_requirements(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('applied', 'rejected', 'accepted', 'completed')),
  decided_by UUID REFERENCES users(id),     -- org (or admin) who accepted/rejected; NULL while the caregiver's own action produced the current status
  applied_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  decline_reason TEXT,                      -- optional here (unlike NurseNow Individual's mandatory JOB_012 rule) — Organisation's applicant review is a free list, not the forced one-at-a-time flow
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(requirement_id, profile_id)
);

CREATE INDEX idx_org_requirement_applications_requirement ON organisation_requirement_applications(requirement_id);
CREATE INDEX idx_org_requirement_applications_profile ON organisation_requirement_applications(profile_id);

-- ============================================
-- APP MIN VERSIONS TABLE (force-upgrade)
-- 2-row singleton (one per platform), seeded at '1.0.0' — see 6.9.
-- ============================================
CREATE TABLE app_min_versions (
  platform VARCHAR(10) PRIMARY KEY CHECK (platform IN ('android', 'ios')),
  min_version VARCHAR(20) NOT NULL,
  store_url TEXT,
  update_message TEXT,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

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
    'profile_updated',
    'status_changed',
    'code_changed',
    'admin_edit_profile',
    'admin_note_added',
    'admin_created',
    'admin_deactivated',
    'phone_changed',
    'edits_acknowledged',
    'job_posted',
    'job_closed',
    'job_response',
    'job_application_decided',
    'job_updated',
    'app_version_updated',
    'org_requirement_posted',
    'org_requirement_updated',
    'org_requirement_rejected',
    'org_requirement_application_decided'
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

Register a new caregiver. There is no separate "Advanced Details" step — every
field is collected here in one call. Documents (selfie, Aadhaar, optional
qualification/other documents) are uploaded via their own endpoints
immediately after, on the same Registration screen.

**Request:**
```json
{
  "phone": "+919876543210",
  "full_name": "Ramesh Kumar",
  "gender": "male",
  "age": 32,
  "languages": ["hindi", "english"],
  "code": "1234",
  "religion": "hindu",
  "preferred_cities": ["bangalore", "mumbai"],
  "highest_qualification": "rn_above_2_years",
  "terms_accepted": true
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
- `phone`: Required, must match `/^\+91[6-9]\d{9}$/`, must be unique **within the NurseJobs bucket** (role=caregiver) — see 3.1's "Phone uniqueness is per app bucket"; the same phone may already be registered as a NurseNow individual/organisation account without conflict.
- `full_name`: Required, 1-100 characters, alphabetic + spaces only.
- `gender`: Required, must be one of: `male`, `female`, `other`.
- `age`: Required, integer, 18-65 inclusive.
- `languages`: Required, array, min 1 item, each must be valid language enum.
- `code`: Required, exactly 4 digits, numeric only (`/^\d{4}$/`). This is the caregiver's login code from their very first session — used with `/auth/login/code` for every subsequent login. Hashed (bcrypt) and stored in `code_hash` at creation.
- `religion`: Required, must be one of: `hindu`, `muslim`, `christian`, `others`. Set once here — locked from self-edit afterward; only admins can change it.
- `preferred_cities`: Optional array (multi-select). If provided, each value must be one of: `bangalore`, `mumbai`, `hyderabad`, `chennai`, `pune`, `delhi`, `gurgaon`. Omitted or `[]` means no preference. Remains editable later via the self-edit endpoint.
- `highest_qualification`: Required, must be a valid qualification enum value. Remains editable later via the self-edit endpoint.
- `terms_accepted`: Required, must be `true`.

**Note:** Selfie and Aadhaar are uploaded separately via `POST /caregiver/profile/selfie` and `POST /caregiver/profile/documents` immediately after registration — both are mandatory, but there's no server-side gate enforcing they exist (same as the existing selfie-upload gap); admin visibility during review covers this.

---

#### POST `/auth/login/code`

Login with phone + 4-digit code. The code is set at registration, so this is the only caregiver login endpoint — there is no phone-only login. Shared identically by caregiver-app, and by nursenow-app for both its individual and organisation account types.

**Request:**
```json
{
  "phone": "+919876543210",
  "code": "1234",
  "app": "nursejobs"
}
```
- `app`: Required, one of `nursejobs` | `nursenow` — since phone is unique per app bucket, not globally (see 3.1's "Phone uniqueness is per app bucket"), this tells the backend which bucket to search: `nursejobs` looks up caregiver accounts only, `nursenow` looks up individual/organisation accounts only. caregiver-app always sends `nursejobs`; nursenow-app always sends `nursenow` regardless of whether the underlying account is individual or organisation.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "access_token": "jwt_token",
    "refresh_token": "refresh_token",
    "verification_status": "available"
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
    "highest_qualification": "rn_above_2_years",
    "religion": "hindu",
    "qualification_document_url": "https://signed-url...",
    "aadhaar_document_url": "https://signed-url...",
    "other_document_urls": ["https://signed-url..."],
    "terms_accepted": true,
    "verification_status": "available",
    "rejection_message": null,
    "preferred_cities": ["bangalore", "mumbai"],
    "preferred_duty_types": ["day_duty", "night_duty"],
    "min_salary_per_day": 1500,
    "min_salary_per_month": null,
    "created_at": "2026-08-01T10:00:00Z"
  }
}
```

**Notes:**
- All fields are always returned in the response. Fields not yet set return `null`. No fields are omitted (`preferred_cities`/`preferred_duty_types` return `[]` rather than `null` when unset).
- `preferred_cities`, `preferred_duty_types`, `min_salary_per_day`, and `min_salary_per_month` are job search preferences (dynamically filter `GET /caregiver/jobs`, see 6.5 below) rather than profile facts — editable anytime via the self-edit endpoint below, no admin approval needed, never affect `verification_status`.
- Document URLs are signed URLs with 1-hour expiry (or `null` if not uploaded).
- `highest_qualification`, `religion`, and `terms_accepted` are always set from registration onward — there's no intermediate state where they're `null` for a normally-registered caregiver.

---

#### PATCH `/caregiver/profile`

Single self-edit endpoint for every caregiver-editable field. Any subset —
only what's provided gets written/diffed. There is no more "basic" vs
"advanced" split (that distinction only existed when Advanced Details was a
separate onboarding stage).

**Request:**
```json
{
  "age": 33,
  "languages": ["hindi", "english", "kannada"],
  "highest_qualification": "rn_above_2_years",
  "preferred_cities": ["bangalore", "mumbai"],
  "preferred_duty_types": ["day_duty", "night_duty"],
  "min_salary_per_day": 1500,
  "min_salary_per_month": 25000
}
```

`full_name`, `gender`, and `religion` are NOT accepted here — all three are
locked from self-edit past registration; only an admin can change them.
Phone and the login code live on their own endpoints (`PATCH
/caregiver/profile/phone`, `PATCH /caregiver/profile/code`) with different
review-trigger semantics.

`preferred_duty_types` accepts any subset of the 3 fixed duty types
(`live_in`/`day_duty`/`night_duty`) — an empty array `[]` is valid and
clears the preference back to "no filter". `min_salary_per_day` and
`min_salary_per_month` are independent optional integers (1–1,000,000,
same range as a job's own `salary_amount`); there is currently no way to
explicitly clear one back to `null` once set — set it low enough to be a
no-op filter, or contact the office. All four are job search preferences
(see `GET /caregiver/jobs` in 6.5) — they share this endpoint's mechanics
exactly (editable anytime, `has_pending_edits` flagged, `verification_status`
untouched except the `rejected` auto-resubmit rule below) even though
they're not profile facts.

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

**Side effects:**
- Audit log entry created with before/after values (only for fields that actually changed).
- Email notification sent to admin with changed fields.
- Profile is flagged as `has_pending_edits = true` in the database.
- **While `available`/`unavailable`, status does NOT change automatically.** Admin reviews the edits and manually decides whether to re-verify.
- **While `rejected`, any actual change here auto-resubmits** — `verification_status` is reset to `pending_call` server-side, no separate "resubmit" action needed. The response's `verification_status` reflects this.

**DO NOT:**
- Do NOT auto-reset verification status on profile edit for `available`/`unavailable` caregivers.
- Do NOT block the caregiver from using the app while edits are pending review.
- Each profile edit re-sets `has_pending_edits = true` even if previously acknowledged.

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
    "verification_status": "pending_call",
    "rejection_message": null,
    "verified_at": null
  }
}
```

---

#### POST `/caregiver/mark-available`

One-click "Available for Jobs" — the caregiver-app's single self-service
action for becoming available again. No request body.

**Precondition/behavior by current status:**
- `unavailable` or `assigned` → sets `verification_status` to `available`,
  audit-logs it. This only flips `caregiver_profiles.verification_status` —
  unlike the admin's dedicated accept/reject-application flow, it does NOT
  touch the job or `job_applications` row (mirrors the scope of the generic
  admin status-override endpoint), so a previously-accepted application
  stays a historical `accepted` record and the job stays closed.
- `available` already → no-op. No DB write, no audit entry.
  `already_available: true` in the response so the UI can show "You are
  already marked as available" without treating it as a failure.
- `pending_call` or `rejected` → `PROFILE_022`. A rejected caregiver must
  instead edit their profile, which auto-resubmits (see PATCH
  `/caregiver/profile`); there's no self-service path out of `pending_call`
  at all.

There is currently no self-service way to go FROM `available` TO
`unavailable` — that direction is still admin-only (via `PATCH
/admin/caregivers/:id/status`).

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Status updated",
    "verification_status": "available",
    "already_available": false
  }
}
```

**Errors:** `PROFILE_019` (no profile), `PROFILE_022` (ineligible current status).

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
- `status` (filter: `pending_call`, `available`, `unavailable`, `assigned`, `rejected`)
- `qualification` (filter by qualification)
- `language` (filter by language, comma-separated for multiple)
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
      "highest_qualification": "rn_above_2_years",
      "verification_status": "pending_call",
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
    "highest_qualification": "rn_above_2_years",
    "religion": "hindu",
    "qualification_document_url": "https://signed-url...",
    "aadhaar_document_url": "https://signed-url...",
    "other_document_urls": ["https://signed-url..."],
    "terms_accepted": true,
    "verification_status": "pending_call",
    "rejection_message": null,
    "preferred_cities": ["bangalore", "mumbai"],
    "admin_notes": {
      "internal_notes": "Good candidate, verified docs look clean",
      "availability_remarks": "Prefers south Bangalore"
    },
    "created_at": "2026-08-01T10:00:00Z",
    "verified_at": null
  }
}
```

---

#### PATCH `/admin/caregivers/:id/status`

Admin override — deliberately unrestricted. Admin can set any caregiver to
any of the 5 statuses, from any current status; there is no transition-
matrix check on this endpoint. The *normal* day-to-day flow, driven by
admin-web's Approve/Reject quick-action buttons (only offered from
`pending_call`), is `pending_call` → `available` or `pending_call` →
`rejected` — everything else (jumping to `assigned`, manually resetting
back to `pending_call`, etc.) is available as a free-form override for
edge cases.

**Request:**
```json
{
  "status": "available",
  "rejection_message": null
}
```

**Validation:**
- `status`: Required, must be one of the 5 valid statuses.
- `rejection_message`: Optional, only relevant when status is `rejected`, max 1000 characters.

**Side effects:**
- If `available`: `verified_at` set, `verified_by` set to admin ID. `rejection_message` cleared. Green icon shown.
- If `rejected`: `rejection_message` set.
- Every other target status: `rejection_message` cleared.
- Push notification sent to caregiver only for `available` and `rejected` targets.
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
  "availability_remarks": "Prefers morning shifts, south Bangalore area"
}
```

**Validation:**
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

### 6.6 Job / Application Endpoints

Admin posts a job built around the care receiver's needs (not a single
"work type" category); caregivers apply/reject; admin accepts one applicant
(closing the job and assigning that caregiver) or, later, rejects an
acceptance (reopening the job). See CLAUDE.md's "Job/Application Flow" for
the full narrative.

#### POST `/admin/jobs`

Create a new job posting (and its 1:1 care receiver). Sends push
notification to ALL caregivers.

**Request:**
```json
{
  "care_receiver": {
    "age": 72,
    "gender": "female",
    "weight_kg": 58,
    "mobility": "walks_with_assistance",
    "communication": "verbal",
    "feeding_type": "oral_needs_assistance",
    "medical_assistance": ["medication_reminders"],
    "has_medical_condition": true,
    "medical_conditions": ["diabetes"],
    "medical_condition_other": null,
    "toilet_assistance": ["uses_diapers"],
    "toilet_assistance_other": null,
    "requires_vital_monitoring": true,
    "vital_monitoring_types": ["blood_pressure", "blood_sugar"]
  },
  "city": "bangalore",
  "area": "Indiranagar",
  "description": "Elderly patient, 72 years, post hip surgery.",
  "duty_type": "live_in",
  "frequency_of_care": "daily",
  "start_date": "2026-08-10",
  "languages": ["kannada", "english"],
  "salary_amount": 30000,
  "preferred_gender": "female",
  "preferred_religion": "hindu"
}
```

**Validation:**
- `care_receiver.age`: Required integer, 1-120. `care_receiver.gender`: Required, valid gender enum (`male`/`female`/`other` — the patient's actual gender, not a preference). `care_receiver.weight_kg`: Required integer, 1-300. These three are the only hard-required care-receiver fields.
- `care_receiver.mobility`/`communication`/`feeding_type`: Optional, valid enum value if provided. If omitted, the backend defaults them to `walks_independently`/`verbal`/`oral_independent` respectively (`CARE_RECEIVER_DEFAULTS` in `jobs.service.ts`) — the persisted/returned value is always a real selection, never null. `feeding_type` alone (`tube_feeding`/`oral_and_tube`) is sufficient — no separate assistance question.
- `care_receiver.medical_assistance`: Optional array, each item a valid enum value. An omitted or empty array defaults to `[medication_reminders]`.
- `care_receiver.has_medical_condition`: Optional boolean, defaults to `false` when omitted.
- `care_receiver.medical_conditions`: Required array if `has_medical_condition` is true; not validated otherwise.
- `care_receiver.medical_condition_other`: Optional free text, max 500 chars. UI-only conditional (admin-web shows/sends it only when `medical_conditions` includes `other`) — the backend itself accepts it unconditionally, no cross-field validation.
- `care_receiver.toilet_assistance`: Optional array, each item a valid enum value — multi-select ("select all that apply"). An omitted or empty array defaults to `[independent]`.
- `care_receiver.toilet_assistance_other`: Optional free text, max 500 chars. Same pattern as `medical_condition_other` — UI-conditional on `toilet_assistance` including `others`, unconditionally optional server-side.
- `care_receiver.requires_vital_monitoring`: Optional boolean, defaults to `false` when omitted. `care_receiver.vital_monitoring_types`: Required non-empty array if `requires_vital_monitoring` is true; not validated otherwise.
- `city`: Required, must be valid city enum. `area`: Required free text (previously optional).
- `description`: Optional free text, max 2000 chars (previously required). UI label shortened to "More details you want to share about patient".
- `duty_type`: Required, must be exactly one of the 3 fixed shifts — `live_in` ("24Hrs - Live In"), `day_duty` ("12Hrs Day Shift, 8am to 8pm"), `night_duty` ("12Hrs Night Shift, 8pm to 8am"). No `other` value, and no separate `start_time`/`end_time` input — the backend derives and stores those from `duty_type`. UI label: "Hours Care Needed".
- `frequency_of_care`: Required, valid enum value — `daily` ("Daily") or `monthly` ("Monthly").
- `start_date`: Required (ISO date, previously optional). UI label: "Preferred Start Date".
- `languages`: Required non-empty array, each item a valid language enum — a multi-select preference, shown to caregivers as informational.
- `salary_amount`: Required integer, 1-1,000,000. Unit follows `frequency_of_care` (₹/day for `daily`, ₹/month for `monthly`) — shown highlighted at the top of the job card in caregiver-app, and dynamically labeled on the admin-web form/job list.
- `preferred_gender`: Optional, `male` or `female` — omitted means no preference. Enforced server-side on `GET /caregiver/jobs`: a caregiver only sees jobs where this is unset or matches their own `caregiver_profiles.gender`.
- `preferred_religion`: Optional, `hindu`/`muslim`/`christian` only (`others` excluded — valid for a caregiver's own religion at registration, not offered as a job preference) — omitted means no preference. Never used as a filter.

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "job_number": 42,
    "admin_job_number": 542,
    "patient_job_number": null,
    "care_receiver_id": "uuid",
    "salary_amount": 30000,
    "posted_at": "2026-08-16T10:00:00Z",
    "status": "active"
  }
}
```

**Side effects:**
- `care_receivers` row created, then `jobs` row referencing it (status `active`).
- Push notification sent to ALL caregivers (background notification — works even if app is closed).
- Notification title: "New Job: Live-In Care in Bangalore"
- Notification body: "Indiranagar, Bangalore | IMMEDIATELY APPLY"
- Audit log entry created (`job_posted`).

---

#### GET `/admin/jobs`

List all job postings (paginated).

**Query Parameters:**
- `page`, `limit`, `sort`, `order` (standard pagination)
- `status` (filter: `active`, `closed`)
- `city` (filter)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "job_number": 42,
      "admin_job_number": 542,
      "patient_job_number": null,
      "care_receiver_id": "uuid",
      "city": "bangalore",
      "area": "Indiranagar",
      "description": "Elderly patient...",
      "duty_type": "live_in",
      "frequency_of_care": "daily",
      "languages": ["kannada", "english"],
      "salary_amount": 30000,
      "preferred_gender": "female",
      "preferred_religion": "hindu",
      "status": "active",
      "posted_at": "2026-08-03T10:00:00Z",
      "created_at": "2026-08-03T10:00:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 10, "totalPages": 1 }
}
```

---

#### GET `/admin/jobs/:id`

Get job detail with the care receiver and every application.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "city": "bangalore",
    "area": "Indiranagar",
    "description": "Elderly patient...",
    "duty_type": "live_in",
    "frequency_of_care": "daily",
    "status": "active",
    "posted_by": "uuid",
    "created_at": "2026-08-03T10:00:00Z",
    "care_receiver": {
      "id": "uuid",
      "age": 72,
      "gender": "female",
      "weight_kg": 58,
      "mobility": "walks_with_assistance",
      "communication": "verbal",
      "feeding_type": "oral_needs_assistance",
      "medical_assistance": ["medication_reminders"],
      "has_medical_condition": true,
      "medical_conditions": ["diabetes"],
      "toilet_assistance": ["uses_diapers"],
      "requires_vital_monitoring": true,
      "vital_monitoring_types": ["blood_pressure", "blood_sugar"]
    },
    "applications": [
      {
        "id": "uuid",
        "profile_id": "uuid",
        "full_name": "Ramesh Kumar",
        "phone": "+919876543210",
        "status": "applied",
        "decided_by": null,
        "decided_by_name": null,
        "applied_at": "2026-08-03T11:00:00Z",
        "accepted_at": null,
        "rejected_at": null,
        "updated_at": "2026-08-03T11:00:00Z"
      }
    ]
  }
}
```

Each application carries the full per-transition timeline (`applied_at`/
`accepted_at`/`rejected_at`, each `null` until that transition happens — same
semantics as `my_application` on `GET /caregiver/jobs`, see below), plus
`decided_by` (the deciding admin's user id, `null` while `status: "applied"`
or when the caregiver self-declined) and `decided_by_name` (that admin's
`full_name`, resolved server-side via a join — `null` under the same
conditions as `decided_by`). This is what lets admin-web show not just that
an application was accepted/rejected, but exactly when and by which admin.

---

#### PATCH `/admin/jobs/:id`

Full edit of an existing job and its care receiver — same request body shape
and validation as `POST /admin/jobs`. Same job id and application history are
preserved (edits never touch existing `job_applications` rows), and this is
allowed regardless of the job's current status or applicant state (including
one already `accepted`/assigned). If the job was `closed`, saving the edit
also **reposts** it: `status` flips back to `active` and the "New Job" push
re-broadcasts to all caregivers (same copy as `POST /admin/jobs`). Editing an
already-`active` job does not resend that push, to avoid spamming caregivers
on every minor edit. Doubles as the "view full job details" surface in
admin-web — the edit form is pre-filled with every current field. A repost
also bumps `posted_at` to NOW(), restarting the caregiver-facing 3-day
apply-by urgency window (a plain edit of an already-active job leaves
`posted_at`, and therefore the window, untouched). `job_number`/
`admin_job_number`/`patient_job_number` never change — set once at
creation, same on every edit or repost.

**Request:** identical shape to `POST /admin/jobs`'s request body (see above).

**Response (200):** the updated `Job` object (same shape as the create
response's `data`).

**Errors:** `GEN_002` if the job doesn't exist; same `GEN_001` validation as
create for any invalid field.

---

#### PATCH `/admin/jobs/:id/close`

Close a job posting manually (no more applications accepted).

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

#### POST `/admin/jobs/:id/remind`

Re-broadcast a push reminder to all caregivers for an active job. `JOB_005` if the job is already closed.

**Response (200):**
```json
{ "success": true, "data": { "message": "Reminder sent" } }
```

---

#### PATCH `/admin/jobs/:jobId/applications/:applicationId`

Admin decision on one applicant. **This is the offer confirmation** — admin
has already contacted the caregiver outside the app before calling this;
there's no separate in-app caregiver "accept offer" step.

**Request:**
```json
{ "status": "accepted" }
```

**Validation:**
- `status`: Required, `accepted` or `rejected` (never `applied` — that's caregiver-only).
- Only two transitions are valid: `applied` → `accepted`/`rejected`, and `accepted` → `rejected` (admin reversing a prior acceptance). Anything else (double-accept, re-deciding an already-rejected application) is `JOB_007`.
- `JOB_006` if the application doesn't exist or doesn't belong to `:jobId`.

**Response (200):**
```json
{ "success": true, "data": { "message": "Application updated", "status": "accepted" } }
```

**Side effects:**
- `applied` → `accepted`: this application's `status`/`decided_by` update; `jobs.status` → `closed` (no further applications accepted); the caregiver's `verification_status` → `assigned`.
- `accepted` → `rejected`: this application's `status`/`decided_by` update; `jobs.status` → `active` again (reopened); the caregiver's `verification_status` → `available`.
- `applied` → `rejected`: just declines that one application — no effect on the job or the caregiver's status.
- Other still-`applied` applications on the same job are left untouched either way.
- Audit log entry created (`job_application_decided`).

---

#### GET `/caregiver/jobs`

List active job postings for caregiver to view and apply. Only jobs whose
`preferred_gender` is unset (no preference) or matches the requesting
caregiver's own `caregiver_profiles.gender` are returned — filtering is
server-side, not a client-side hide. Also filtered dynamically by the
caregiver's own job search preferences (all optional, set via `PATCH
/caregiver/profile` — see 6.4): a job is hidden unless its `city` is in the
caregiver's `preferred_cities` (or that list is empty), its `duty_type` is
in `preferred_duty_types` (or that list is empty), and its `salary_amount`
meets the caregiver's threshold for its own `frequency_of_care`
(`min_salary_per_day` for a `daily` job, `min_salary_per_month` for a
`monthly` job — each independently nullable, never cross-applied to the
other frequency). All of this is read fresh from the caregiver's current
profile on every request — changing a preference takes effect on the very
next fetch. Each item
includes the full `care_receiver` (joined via `care_receiver_id`, not just
on `GET /admin/jobs/:id`) — the caregiver-app renders it under the same
two section labels as the admin form: **About Patient** (age, gender,
weight, mobility, communication, feeding, medical assistance, medical
condition(s) + info, toilet assistance, vital monitoring), and **About
Nurse/Caregiver Requirement** (duty type, area,
language/gender/religion preferences) — so every detail admin entered is
visible directly on the jobs list, no separate detail screen. The
caregiver-app also shows the job's display id (`jobDisplayId()` —
"ADMIN-JOB-<n>"/"PAT-JOB-<n>" depending on who posted it) and `salary_amount`
(unit — ₹/day or ₹/month — follows `frequency_of_care`) highlighted at the
top of each card, plus a 3-day apply-by urgency message
computed client-side from `posted_at` (`posted_at + 3 days`, shown as days
remaining — purely informational, never blocks applying).

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "job_number": 42,
      "admin_job_number": 542,
      "patient_job_number": null,
      "city": "bangalore",
      "area": "Indiranagar",
      "description": "Elderly patient...",
      "duty_type": "live_in",
      "frequency_of_care": "daily",
      "languages": ["kannada", "english"],
      "salary_amount": 30000,
      "preferred_gender": "female",
      "preferred_religion": "hindu",
      "posted_at": "2026-08-03T10:00:00Z",
      "created_at": "2026-08-03T10:00:00Z",
      "my_application": null,
      "care_receiver": {
        "id": "uuid",
        "age": 72,
        "gender": "female",
        "weight_kg": 58,
        "mobility": "walks_with_assistance",
        "communication": "verbal",
        "feeding_type": "oral_needs_assistance",
        "medical_assistance": ["medication_reminders"],
        "has_medical_condition": true,
        "medical_conditions": ["diabetes"],
        "toilet_assistance": ["uses_diapers"],
        "requires_vital_monitoring": true,
        "vital_monitoring_types": ["blood_pressure", "blood_sugar"]
      }
    }
  ]
}
```

**Notes:**
- `my_application` is `null` if the caregiver hasn't applied yet, otherwise `{ status, applied_at, accepted_at, rejected_at, decided_by_admin }` — the real per-transition timeline, not just the current status. `status` is `"applied"` / `"rejected"` / `"accepted"`. Each `_at` field is `null` until that transition has happened (e.g. `accepted_at` stays `null` if the application was rejected without ever being accepted). `decided_by_admin` is `true` whenever an admin's decision (not the caregiver's own action) produced the current status — covers both "admin rejected a still-applied application" and "admin undid a prior acceptance"; both cases should read to the caregiver as "declined by the employer", not "you declined". This was added specifically because a bare status string couldn't distinguish a caregiver's own self-decline from an admin un-accepting them — both landed on `status: "rejected"` and rendered identically.
- Viewable at any verification status — browsing motivates onboarding. Only applying is gated.
- `care_receiver` is always present (every job has exactly one, `care_receiver_id` is `NOT NULL`) — unlike on `GET /admin/jobs` (list), which does NOT join it, matching the admin list view's summary-row style; admin gets full details via `GET /admin/jobs/:id` or the Edit dialog.

---

#### GET `/caregiver/jobs/assigned`

The job the caregiver is currently (or was most recently) assigned to and
accepted for. This endpoint exists because `GET /caregiver/jobs` only lists
*active* jobs, and accepting an application immediately closes the job — so
without this, an assigned caregiver would have no way to see their own
job's details again once it closes. Caregiver-only, no query params.

**Response (200) — has an assignment:** the full `Job` object (same shape
as `POST /admin/jobs`'s response, including the joined `care_receiver`),
regardless of the job's current `status`, plus `job_poster: { full_name,
phone }` — the posting admin's contact info (nothing else — never their
password/code hash or fcm_token), `null` if that admin account no longer
exists. `job_poster` is only ever included here, never on `GET
/caregiver/jobs` (the browse list) — admin contact info is only shared
once there's an actual accepted engagement between the two.

**Response (200) — no assignment:**
```json
{ "success": true, "data": null }
```
Not a 404 — "never been accepted onto a job" is the normal state for most caregivers.

**Resolution when there's ambiguity:** picks the `job_applications` row
with `status = 'accepted'` and the most recent `updated_at` for this
caregiver. In practice there's at most one such row at a time, but this
ordering also protects against a rare edge case: the generic admin
status-override endpoint (`PATCH /admin/caregivers/:id/status`) doesn't
cascade into `job_applications`, so if an admin ever unassigns a caregiver
through that route instead of the dedicated accept/reject-application flow,
a stale `accepted` row could be left behind — the most-recent-first
ordering ensures a later acceptance on a different job still wins.

---

#### POST `/caregiver/jobs/:id/apply`

Apply to (or reject) a job posting. Caregiver can call this multiple times — the same application row is updated in place, not duplicated.

**Request:**
```json
{ "status": "applied" }
```

**Validation:**
- `status`: Required, must be `applied` or `rejected` (`accepted` is admin-only — see the decide-application endpoint above).
- Job must be `active` (`JOB_002` otherwise).
- Caregiver must have status `available` or `assigned` to apply. `unavailable`/`pending_call`/`rejected` caregivers cannot (`JOB_001`) — they must toggle back to `available` first.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Application recorded",
    "status": "applied"
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
      "job_number": null,
      "admin_job_number": null,
      "patient_job_number": null,
      "job_id": null,
      "before_value": { "verification_status": "pending_call" },
      "after_value": { "verification_status": "available" },
      "ip_address": "192.168.1.1",
      "created_at": "2026-08-01T14:30:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 100, "totalPages": 5 }
}
```

`job_number`/`admin_job_number`/`patient_job_number`/`job_id` are resolved
server-side (not stored columns — a query-time join in
`AuditLogsRepository.list`), so admin-web can render the job's display id
("ADMIN-JOB-<n>"/"PAT-JOB-<n>", picking whichever of
`admin_job_number`/`patient_job_number` is non-null) and link straight to
that job instead of a bare entity_type/entity_id UUID, which was otherwise
unreadable. All three number fields are `null` for every entity_type
except two: `entity_type = 'jobs'` (entity_id is the job itself —
`job_posted`/`job_updated`/`job_closed`/`job_reminder_sent`) and
`entity_type = 'job_applications'` (entity_id is the application; resolved
one hop further via `job_applications.job_id` —
`job_response`/`job_application_decided`).

**DO NOT:**
- Do NOT allow caregivers to access audit logs.
- Do NOT provide CSV/Excel export functionality in V1.

---

### 6.9 App Version / Force-Upgrade Endpoints

Lets an admin force caregivers on an old build to update before they can use
the app again. `app_min_versions` is a 2-row singleton table (one row per
platform, seeded at `1.0.0`), not something admins create/delete — only
`PATCH` per platform.

#### GET `/app-versions/check`

**Public — no auth.** Called by the caregiver app on every cold launch,
before the splash screen even loads the session (`AppVersionRepository
.checkForUpdate()`), so a caregiver who's never logged in still gets
blocked on a too-old build. The caregiver app fails open on any error here
(network down, unexpected response) — this check must never be able to
lock every caregiver out by itself.

**Query Parameters:**
- `platform` (required) — `android` | `ios`
- `version` (required) — the installed build's version string (e.g. `"1.2.0"`, from `PackageInfo.version`)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "update_required": true,
    "min_version": "1.2.0",
    "store_url": "https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs",
    "update_message": "Please update to continue using NurseJobs."
  }
}
```
`store_url`/`update_message` are only populated when `update_required` is
`true`; otherwise both are `null`. Version comparison is numeric
major/minor/patch (not lexicographic — `2.10.0` beats `2.9.0`); an
unparseable segment counts as `0` rather than throwing.

**Errors:** `GEN_001` (missing/malformed `platform` or `version` — an unrecognized platform is rejected here too, by DTO validation, before ever reaching the lookup).

---

#### GET `/admin/app-versions`

Admin or super_admin. Lists both platform rows.

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "platform": "android",
      "min_version": "1.2.0",
      "store_url": "https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs",
      "update_message": "Please update to continue using NurseJobs.",
      "updated_by_name": "Admin One",
      "updated_at": "2026-08-17T10:00:00Z"
    },
    {
      "platform": "ios",
      "min_version": "1.0.0",
      "store_url": null,
      "update_message": null,
      "updated_by_name": null,
      "updated_at": "2026-08-01T00:00:00Z"
    }
  ]
}
```

#### PATCH `/admin/app-versions/:platform`

Admin or super_admin. `:platform` is `android` or `ios`; anything else
returns `GEN_002` (there's simply no matching row to update). Audit-logs
`app_version_updated` with before/after `min_version`/`store_url`.

**Request Body:**
```json
{
  "min_version": "1.3.0",
  "store_url": "https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs",
  "update_message": "Please update to continue using NurseJobs."
}
```
`min_version` is required, `x.y.z` format only (`GEN_001` otherwise).
`store_url`/`update_message` are optional free text.

**Response (200):** the updated row, same shape as one item of the `GET` list above.

**DO NOT:**
- Do NOT gate this behind super_admin only — any admin can raise/lower the bar (same trust level as posting/editing jobs).
- Do NOT add an equivalent gate to admin-web — it's a web app, a browser reload picks up a new deploy, there's no store binary to be "behind" on.

---

### 6.10 NurseNow Individual Endpoints

See "NurseNow" in CLAUDE.md for the full design context. `@Roles(UserRole.INDIVIDUAL)`,
`src/individual/`. This covers the Individual (patient/family) account type; the Organisation
(hospital/rehab/clinic) account type — built on its own dedicated tables/codepath rather than
reusing jobs/care_receivers — is documented separately in 6.11.

Registration/login reuse the auth endpoints in 6.3: `POST /auth/register/individual`
(`phone`, `full_name`, `code`) and `POST /auth/login/code` (shared with caregiver login, same
phone+4-digit-code mechanic, non-expiring token, called with `app: 'nursenow'` — see 3.1's
"Phone uniqueness is per app bucket"). Phone dedup on registration checks only the NurseNow
bucket (individual + organisation), so the same phone may already hold a separate NurseJobs
caregiver account without conflict.

#### GET `/individual/me`

Returns the caller's own account: `{ user_id, patient_number, full_name, phone,
is_job_posting_blocked }`. `patient_number` is the raw integer backing the "PAT-<n>" display id
(migration 046, starts at 500) — see CLAUDE.md's "Human-friendly sequential display IDs".

#### POST `/individual/requirements`

Creates a new requirement. Same request shape as `POST /admin/jobs` (6.6) — `care_receiver`,
`city`, `area`, `description`, `duty_type`, `start_date`, `languages`, `preferred_gender`,
`preferred_religion` — **except no `frequency_of_care`/`salary_amount`**, which admin sets on
approval. Always created with `status: 'pending_review'`.

**Errors:** `JOB_009` (already have a `pending_review`/`active` requirement), `JOB_010`
(`is_job_posting_blocked`), plus the same field-validation errors as `POST /admin/jobs`.

#### GET `/individual/requirements`

The caller's **full requirement history** — every past posting stays visible (not just the
current one), so a past requirement's full detail and applicants (including who was accepted)
remain visible after it closes. Each item has its `care_receiver` joined in (unlike
`GET /caregiver/jobs`'s list form, this one always includes it — an individual has realistically
few historical postings, so the per-item join cost is negligible). Once `active`,
`frequency_of_care`/`salary_amount` are populated (admin-set on approval); while `pending_review`
they're `null`. A `closed` requirement that was declined carries `rejection_reason`. The account
may have at most one **live** requirement (`pending_review` or `active`) at a time (`JOB_009`) —
closed/rejected ones never block posting again.

#### GET `/individual/requirements/:id/applications`

Applicants on the caller's own requirement — same shape as `GET /admin/jobs/:id`'s `applications`
array (6.6). `GEN_002` if the requirement isn't found or isn't owned by the caller. Callable
regardless of the requirement's status — including `closed`, so the accepted (or declined)
applicant list stays visible after the requirement closes, not just while it's `active`.

#### GET `/individual/requirements/:jobId/applications/:applicationId/profile`

An applicant's full profile — ownership-checked both ways (the requirement is this individual's
own, and the application actually belongs to it; `GEN_002` otherwise). Delegates to
`CaregiverService.getApplicantProfile`, which returns a deliberately trimmed subset of a
caregiver's own `GET /caregiver/profile` shape: no `email`, no `aadhaar_document_url`/
`qualification_document_url`/`other_document_urls`, no `preferred_cities`/
`preferred_duty_types`/`min_salary_per_day`/`min_salary_per_month`, no `rejection_message` —
none of that is an outside viewer's business. nursenow-app's `JobsPostedScreen` only exposes this
via a "View Profile" button on the single candidate currently under forced one-at-a-time review
(`_ReviewingApplicantTile`), pushing the new shared `CaregiverProfileViewScreen`.

#### PATCH `/individual/requirements/:jobId/applications/:applicationId`

Accept/reject an applicant — same body/behavior as the admin decide-application endpoint (6.6):
accepting closes the requirement and assigns the caregiver; rejecting a still-`applied` applicant
just declines them. Ownership-checked (`GEN_002` if not the requirement's owner); admin can do the
exact same decision via the regular `PATCH /admin/jobs/:jobId/applications/:applicationId`.
**Unlike admin's flow, rejecting here requires a non-blank `reason` in the request body —
`JOB_012` otherwise.** This is enforced in `IndividualService.decideMyApplication`, not in the
shared `DecideApplicationDto` (there `reason` is optional, so admin's own reject stays as-is).
The reason is stored in `job_applications.decline_reason` and returned on subsequent
`GET .../applications` calls, so the individual can see what they wrote after the fact.

#### PATCH `/individual/profile/phone` + PATCH `/individual/profile/code`

Self-service phone number and 4-digit login PIN change — reuse caregiver's `UpdatePhoneDto`
(`{ phone }`) / `UpdateCodeDto` (`{ code }`) unchanged (role-agnostic regex validators). Unlike
the caregiver equivalent, neither ever triggers a re-review reset — an individual account has no
verification pipeline to send back. Phone: no-op if unchanged; `AUTH_001` if the new number is
already registered to another account. Both audit-log (`phone_changed`/`code_changed`,
`entity_type: 'individual_profiles'`).

**Admin-side additions supporting the above** (still under 6.5/6.6, not new endpoints):
- Approving a `pending_review` requirement is just editing it — `PATCH /admin/jobs/:id`
  (6.6) with the full shape including `frequency_of_care`/`salary_amount` transitions
  `pending_review → active`, reusing the same repost/push-broadcast path a `closed → active`
  edit already used.
- `PATCH /admin/jobs/:id/reject` (`{ reason }`, admin/super_admin) — declines a `pending_review`
  requirement: `status → closed`, `rejection_reason` set. `JOB_011` if not `pending_review`.
- `GET /admin/jobs` (6.6) accepts an optional `posted_by_role` filter and every job in the
  response now includes `posted_by_role`/`posted_by_name` (joined from `users`), so admin-web can
  distinguish "posted by patient/family" from "posted by admin" inline.
- `GET /admin/individuals`, `GET /admin/individuals/:id`, `PATCH /admin/individuals/:id/block`
  (`{ level: 'job_posting' | 'full', reason }`), `PATCH /admin/individuals/:id/unblock` —
  admin/super_admin, backs admin-web's "Patients/Family" tab. `job_posting` block only stops new
  postings (`JOB_010`, existing live requirement keeps working); `full` block sets
  `users.is_active = false` (total login lockout, `AUTH_004`).

---

### 6.11 NurseNow Organisation Endpoints

See "NurseNow" in CLAUDE.md for the full design context. `@Roles(UserRole.ORGANISATION)`,
`src/organisation/`. **Entirely separate tables/codepath from jobs/care_receivers/
job_applications** (which Individual reuses, 6.10) — `organisation_profiles`,
`organisation_requirements`, `organisation_requirement_applications` (migration 041), mirroring
the *shape* of the jobs pipeline (same `pending_review → active → closed` status values, same
`applied/rejected/accepted/completed` application states, `decline_reason` from day one) without
reusing any of its tables. A requirement has no `care_receiver`, no `city`/`area`/`duty_type` —
those are collected once at org registration and every requirement inherits them from the org's
own `organisation_profiles` row. **Unlike Individual, there is no one-live-requirement limit** —
an org can have many simultaneous `pending_review`/`active` requirements at once, a deliberate
scope difference (a hospital/rehab genuinely needs to fill several openings simultaneously).

Registration/login reuse the auth endpoints in 6.3: `POST /auth/register/organisation`
(`phone`, `code`, `organisation_name`, `contact_person_name`, `organisation_type`, `city`,
`area`) and `POST /auth/login/code` (shared with caregiver/individual login, same
phone+4-digit-code mechanic, non-expiring token, called with `app: 'nursenow'` — see 3.1's
"Phone uniqueness is per app bucket"). Phone dedup on registration checks only the NurseNow
bucket (individual + organisation), so the same phone may already hold a separate NurseJobs
caregiver account without conflict. `organisation_type` is one of
`hospital`/`rehab`/`clinic`. `city` accepts the existing 7 cities plus `others`
(`ORGANISATION_CITY_OTHERS`) — a separate org-scoped list validated at the DTO layer, not an
extension of the shared `City` enum. Response on success: `{ user_id, access_token,
refresh_token }` — no `verification_status`, same as Individual registration.

#### GET `/organisation/me`

Returns the caller's own account: `{ user_id, org_number, organisation_name,
contact_person_name, organisation_type, city, area, phone, is_job_posting_blocked }`.
`org_number` is the raw integer backing the "ORG-<n>" display id (migration 046, starts at
500) — see CLAUDE.md's "Human-friendly sequential display IDs".

#### POST `/organisation/requirements`

Creates a new requirement. Request body (`CreateOrganisationRequirementDto`): `type_of_nurse`
(one of the 12 `TypeOfNurse` values), `accommodation_provided` (boolean), `food_provided`
(boolean), `special_skills` (optional, free text, max 1000 chars) — **no `care_receiver`, no
`city`/`area`/`duty_type`** (inherited from the org's profile), and **no
`frequency_of_care`/`salary_amount`/`start_date`**, which admin sets during approval. Always
created with `status: 'pending_review'`. No one-live-requirement check (unlike `JOB_009` on
Individual's equivalent endpoint).

**Errors:** `JOB_010` (`organisation_profiles.is_job_posting_blocked = true`), plus standard
field-validation (`GEN_001`).

#### GET `/organisation/requirements`

The caller's **full requirement history** — every past posting, not just current ones, newest
first (`ORDER BY created_at DESC`). Once `active`, `frequency_of_care`/`salary_amount`/
`start_date` are populated (admin-set on approval); while `pending_review` they're `null`. A
`closed` requirement that was declined carries `rejection_reason`.

#### GET `/organisation/requirements/:id/applications`

Applicants on the caller's own requirement — each item carries the caregiver's `full_name`/
`phone` plus the full application timeline (`applied_at`/`accepted_at`/`rejected_at`/
`completed_at`) and `decided_by_name` (resolved via a join, `null` while undecided). `GEN_002` if
the requirement isn't found or isn't owned by the caller. Callable regardless of the
requirement's status, so the applicant list (including who was accepted) stays visible after the
requirement closes.

#### GET `/organisation/requirements/:requirementId/applications/:applicationId/profile`

An applicant's full profile — same trimmed shape and both-ways ownership check as Individual's
equivalent endpoint above. Since Organisation's applicant review is a free list (not forced
one-at-a-time), nursenow-app's `RequirementsPostedScreen` exposes a "View Profile" button on
**every** applicant in `_ApplicantTile`, decided or not — not just one candidate at a time.

#### PATCH `/organisation/requirements/:requirementId/applications/:applicationId`

Accept/reject an applicant — same body as the admin decide-application endpoint
(`DecideApplicationDto`: `{ status: 'accepted' | 'rejected', reason? }`). Ownership-checked
(`GEN_002` if not the requirement's owner), then delegates to the same
`OrganisationRequirementsService.decideApplication` method admin's own decide-application
endpoint calls (accepting closes the requirement and sets the caregiver's `verification_status`
to `assigned`; rejecting a still-`applied` applicant just declines them; rejecting a previously
`accepted` applicant reopens the requirement and returns the caregiver to `available`).
**Unlike Individual's equivalent endpoint, `reason` is optional here** — Organisation's
applicant review is a free list, not Individual's forced one-at-a-time/mandatory-reason flow
(see "NurseNow" in CLAUDE.md for why this asymmetry is deliberate, not an oversight).
`JOB_006` if the application isn't found or doesn't belong to the requirement; `JOB_007` if
already decided in a way that doesn't match one of the three valid transitions
(applied→accepted, applied→rejected, accepted→rejected/undo).

#### PATCH `/organisation/profile/phone` + PATCH `/organisation/profile/code`

Self-service phone number and 4-digit login PIN change — reuse caregiver's `UpdatePhoneDto`
(`{ phone }`) / `UpdateCodeDto` (`{ code }`) unchanged, same as Individual's equivalent (6.10).
No re-review logic — an organisation account has no verification pipeline to send back. Phone:
no-op if unchanged; `AUTH_001` if the new number is already registered to another account. Both
audit-log (`phone_changed`/`code_changed`, `entity_type: 'organisation_profiles'`).

#### Caregiver-facing (`src/organisation/caregiver-organisation-requirements.controller.ts`, `@Roles(UserRole.CAREGIVER)`)

Backs caregiver-app's Jobs/MyJobs tabs, **merged into the same list as admin/individual jobs** —
not a separate tab (an earlier iteration gave organisation requirements their own 4th
"Organisation Openings" bottom-nav tab; reversed on explicit follow-up request so a caregiver
only has to check one place — see 12.4/12.3).

- **GET `/caregiver/organisation-requirements`** — every `active` requirement, joined with its
  posting org's `organisation_name`/`organisation_type`/`city`/`area`, plus (as of the Jobs/
  Openings merge) a per-caregiver `my_application` LEFT JOIN identical to
  `GET /caregiver/jobs`'s — `null` if the caller hasn't applied, otherwise the same
  `{status, applied_at, accepted_at, rejected_at, completed_at, decided_by_admin}` shape. Unlike
  `GET /caregiver/jobs`, there is still **no per-caregiver filtering** (no gender/preferred-city/
  preferred-duty-type/salary filtering equivalent) — every caregiver sees every active
  requirement.
- **GET `/caregiver/organisation-requirements/assigned`** — as of the Jobs/Openings merge,
  reshaped to mirror `GET /caregiver/jobs/assigned`'s shape exactly: each item is a full
  requirement record (not a bare `organisation_requirement_applications` row) with a non-null
  `my_application` embedded, joined with the posting org's identity/location — this lets
  caregiver-app's merged MyJobs list render a job and an assigned requirement with the same
  timeline-rendering logic. Same array-of-`accepted`-or-`completed` shape/ordering as before
  (oldest-decision-first by `updated_at`). Still does **not** additionally join in the posting
  organisation's own contact info the way `GET /caregiver/jobs/assigned`'s `job_poster` does for
  jobs — that gap wasn't part of this merge.
- **POST `/caregiver/organisation-requirements/:id/apply`** — same `ApplyJobDto` body
  (`{ status: 'applied' | 'rejected' }`) and eligibility rule as jobs (`available`/`assigned`
  only, `JOB_001` otherwise); `JOB_002` if the requirement isn't `active`. Response:
  `{ message, status }`.
- **POST `/caregiver/organisation-requirements/:id/complete`** — caregiver-only, no body. Mirrors
  `POST /caregiver/jobs/:id/complete` exactly: flips that one application to `completed`
  (`completed_at` stamped) and drops `verification_status` back to `available` only once no other
  `accepted` applications remain (across both jobs and organisation requirements — they share the
  same `caregiver_profiles.verification_status` field). `JOB_008` if there's no active accepted
  application for that requirement. Response: `{ message, verification_status }`.

#### Admin-facing (`src/organisation/admin-organisation-requirements.controller.ts`,
`admin/admin-organisations.controller.ts` — admin/super_admin)

- **`GET /admin/organisation-requirements`** (optional `status` query filter, paginated) /
  **`GET /admin/organisation-requirements/:id`** (adds the full `applications` array plus
  `organisation_name`/`organisation_type`/`city`/`area` joined from the posting org).
- **`PATCH /admin/organisation-requirements/:id`** — the approval path, same "edit with full
  shape" pattern as Individual (6.10): body requires `type_of_nurse`, `frequency_of_care`,
  `salary_amount`, `accommodation_provided`, `food_provided`, `schedule_type`, plus optional
  `special_skills`. `schedule_type` is `date_range` or `specific_days` — **replaces the old
  single "Preferred Start Date" field entirely for organisation requirements** — and gates which
  further fields are required: `date_range` requires `start_date` + `end_date` (`end_date` before
  `start_date` → `ORG_001`); `specific_days` requires `schedule_repeat` (`weekly` or `monthly`)
  plus a non-empty `specific_days` array whose valid range depends on it — ISO weekday numbers
  1-7 (Mon-Sun) if `weekly` (a value outside 1-7 → `ORG_002`), or day-of-month numbers 1-31 if
  `monthly`. Only the active mode's fields are persisted; the other mode's columns are stored/left
  `null` regardless of what's sent. Transitions `pending_review` (or a
  `closed` requirement) to `active` and stamps `posted_at` — activating sends the `"New
  Organisation Opening"` push to all caregivers; a plain edit of an already-`active` requirement
  does not resend it.
- **`PATCH /admin/organisation-requirements/:id/reject`** (`{ reason }`, reusing `RejectJobDto`)
  — sets `status: 'closed'` + `rejection_reason`. `JOB_011` if not currently `pending_review`.
- **`PATCH /admin/organisation-requirements/:requirementId/applications/:applicationId`** — the
  same `OrganisationRequirementsService.decideApplication` the org itself calls; admin has full
  parity to decide an application on any organisation-posted requirement.
- **`GET /admin/organisations`** (paginated) / **`GET /admin/organisations/:id`** — list/detail
  of every organisation account (`user_id, full_name, phone, organisation_name,
  organisation_type, city, area, is_active, is_job_posting_blocked, block_reason, created_at`),
  backs admin-web's "Rehab/Hospitals" tab.
- **`PATCH /admin/organisations/:id/block`** (`{ level: 'job_posting' | 'full', reason }`) /
  **`PATCH /admin/organisations/:id/unblock`** (`{ level }`) — reuses the exact same
  `BlockIndividualDto`/`UnblockIndividualDto` Individual's block endpoints use (role-agnostic).
  `job_posting` block only stops new `POST /organisation/requirements` (`JOB_010`) — existing
  live requirements and their applications keep working; `full` block sets `users.is_active =
  false` (total login lockout, `AUTH_004`).

---

## 7. Error Catalog

### 7.1 Authentication Errors (AUTH_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| AUTH_001 | 409 | Phone number is already registered | Registration with a phone that already has an account **in the same app bucket** — see 3.1's "Phone uniqueness is per app bucket". A phone with a NurseJobs caregiver account can still register a NurseNow account (or vice versa) without hitting this |
| AUTH_002 | 404 | No account found with this phone number | Login with a phone that has no account **in the requested `app` bucket** (`POST /auth/login/code`'s `app` field) — e.g. a phone with only a NurseNow account gets this when logging in with `app: 'nursejobs'` |
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
| PROFILE_009 | 400 | Terms and conditions must be accepted | terms_accepted is false (registration) |
| PROFILE_010 | 400 | Invalid religion value | Religion not in enum (registration) |
| PROFILE_016 | 400 | Code must be exactly 4 digits | Code not matching /^\d{4}$/ |
| PROFILE_018 | 400 | Invalid qualification value | Qualification not in allowed list (registration or self-edit) |
| PROFILE_019 | 404 | Caregiver profile not found | Profile ID doesn't exist |
| PROFILE_020 | 400 | Name must contain only alphabetic characters and spaces | Invalid characters in name |
| PROFILE_021 | 400 | FCM token is required | Empty/missing token on `PUT /caregiver/fcm-token` |
| PROFILE_022 | 400 | Cannot mark yourself available from your current status | `POST /caregiver/mark-available` while pending_call or rejected |

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
| ADMIN_001 | 400 | Invalid status transition from {current} to {requested} | Invalid status value on `PATCH /admin/caregivers/:id/status` |
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
| JOB_001 | 403 | Cannot apply to jobs until your profile is verified | Non-available/assigned caregiver trying to apply |
| JOB_002 | 400 | Job is closed and no longer accepting applications | Applying to a closed job |
| JOB_004 | 400 | Invalid application status value | status not in enum, or caregiver sending `accepted` |
| JOB_005 | 400 | Cannot send a reminder for a closed job | POST .../remind on a closed job |
| JOB_006 | 404 | Application not found | decide-application on a missing/mismatched application id |
| JOB_007 | 400 | Application has already been decided | double-accept, or re-deciding an already-rejected application |
| JOB_008 | 400 | No active accepted application found for this job | caregiver `POST .../complete` when never applied, still `applied`, already `rejected`, or already `completed` |
| JOB_009 | 400 | You already have a requirement in progress | NurseNow individual `POST /individual/requirements` while a `pending_review`/`active` requirement already exists |
| JOB_010 | 403 | Your account is blocked from posting new requirements | NurseNow individual with `individual_profiles.is_job_posting_blocked = true`, or NurseNow organisation with `organisation_profiles.is_job_posting_blocked = true` (`POST /organisation/requirements`, 6.11) |
| JOB_011 | 400 | Only a pending-review requirement can be rejected | `PATCH /admin/jobs/:id/reject` on a job not in `pending_review`, or `PATCH /admin/organisation-requirements/:id/reject` (6.11) on a requirement not in `pending_review` |
| JOB_012 | 400 | A reason is required when declining an applicant | NurseNow individual `PATCH /individual/requirements/:jobId/applications/:applicationId` with `status: 'rejected'` and no/blank `reason` — admin's equivalent admin-web decision stays reason-optional. **Not reused by NurseNow Organisation** (6.11) — an org's/admin's decision on an organisation requirement's applicant stays reason-optional, matching admin's own jobs-decision UX (a deliberate asymmetry, not an oversight) |

### 7.5a NurseNow Organisation Errors (ORG_xxx)

| Code | HTTP Status | Message | When |
|------|-------------|---------|------|
| ORG_001 | 400 | End date cannot be before start date | `PATCH /admin/organisation-requirements/:id` (6.11) with `schedule_type: 'date_range'` and `end_date` earlier than `start_date` |
| ORG_002 | 400 | Weekday values must be between 1 (Monday) and 7 (Sunday) | `PATCH /admin/organisation-requirements/:id` (6.11) with `schedule_type: 'specific_days'`, `schedule_repeat: 'weekly'`, and a `specific_days` value outside 1-7 |

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
| Status: Available | Caregiver | Profile Approved | Congratulations! Your profile has been verified. You are now available for work assignments. |
| Status: Rejected | Caregiver | Profile Update Required | Your profile needs updates. Please check the app for details. |
| New Job Posted | All Caregivers | New Job: {duty_type_display} in {city_display} | {area, }{city_display} \| IMMEDIATELY APPLY |
| Job Reminder | All Caregivers | Reminder: {duty_type_display} in {city_display} | {area, }{city_display} \| APPLY NOW BEFORE IT'S FILLED |
| Daily Availability Reminder (8 AM IST cron, `@nestjs/schedule`) | Caregivers with status available/unavailable only | Update your availability | Confirm your status for today — mark yourself available to keep getting job matches. |

**Payload Structure:**
```json
{
  "notification": {
    "title": "Profile Approved",
    "body": "Congratulations! Your profile has been verified. You are now available for work assignments."
  },
  "data": {
    "type": "status_change",
    "status": "available",
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
- `type: "status_change"` + `status: "available"` → Navigate to Home screen.
- `type: "status_change"` + `status: "rejected"` → Navigate to Profile screen (shows rejection message).

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
Religion: {religion}

Status: Pending Call

Please call to verify their phone number and review their submitted profile and documents in the admin dashboard.

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
| `registration` | `users` | after: new user data (including religion, highest_qualification) |
| `login` | `users` | after: { timestamp, method } |
| `profile_updated` | `caregiver_profiles` | before/after: changed fields only |
| `status_changed` | `caregiver_profiles` | before/after: status + who changed it |
| `code_changed` | `users` | after: { timestamp, changed_by } |
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
| 8 | Rejection Details | `/rejection` | Authenticated, status = rejected |
| 9 | Home | `/home` | Authenticated, status = available/assigned |
| 9a | Jobs Dashboard | `/jobs` | Authenticated, any status (view jobs; respond only if available/assigned) — lists admin/individual jobs AND NurseNow Organisation-posted requirements together (separate backend table, merged client-side; see 6.11) |
| 10 | Profile View | `/profile` | Authenticated, any status |
| 11 | Edit Profile (incl. document upload) | `/profile/edit` | Authenticated, any status |
| 14 | Settings | `/settings` | Authenticated |

There is no "Advanced Details" screen or route — every field (including
documents) is collected on the Registration screen itself.

### 12.2 Navigation Flow

Before any of the below: Splash calls `GET /app-versions/check` (see 6.9).
If the installed build is below the admin-configured minimum, Splash shows
a blocking `UpdateRequiredScreen` instead — no token check, no navigation,
nothing else loads until the caregiver updates. Otherwise (including on
any error from that check — fails open) navigation proceeds as normal:

```
App Launch → Splash
  ├── No token → Login
  │     ├── "Register" tap → Registration (collects everything, incl. documents)
  │     └── Successful login → Route by status (see below)
  └── Has valid token → Route by status

Route by verification_status:
  ├── pending_call → Pending Call screen
  ├── rejected → Rejection Details
  │     └── "Edit & Resubmit" → Edit Profile
  │           — editing any field auto-resubmits (sends status back to
  │             pending_call) server-side; there's no separate "resubmit" flow
  ├── available → Home
  ├── assigned → Home
  └── unavailable → Home (greyed out / not taking work)
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
- Fields, in order: Full Name, Phone (+91), 4-Digit Login Code (numeric PIN input, obscured, right after phone number) — this is the code the caregiver will use with their phone number to log in from here on — Gender (dropdown), Age (number input), Languages (multi-select chips), Religion (dropdown: Hindu, Muslim, Christian, Others, mandatory), Highest Qualification (dropdown, mandatory), Preferred City (multi-select chips: Bangalore, Mumbai, etc., optional), Terms & Conditions (checkbox with link, mandatory). father_name, father_phone, current_address, and notes have been removed from the product entirely.
- "Take Selfie" button → opens camera (NOT gallery). Use Flutter `ImagePicker` with `source: ImageSource.camera`. Do NOT offer `ImageSource.gallery` option. No server-side EXIF validation — this is client-side enforcement only.
- Document upload, inline on this same screen (no separate page/navigation):
  - Aadhaar Card (mandatory): upload button + status indicator.
  - Qualification Document (optional): upload button + status indicator.
  - Other Documents (optional): up to 3 upload slots.
  - Each upload shows a progress indicator and updates in place.
- "Register" button (disabled until Aadhaar is uploaded and all other required fields are filled — qualification document/other documents are not required).
- On success → navigate to Pending Call screen.

#### Pending Call (`/pending-call`)
- Display message: "Thank you for registering! You will receive a call from our office shortly to verify your phone number."
- Show caregiver's registered name and phone.
- No action buttons. This is a waiting screen.
- Pull-to-refresh to check if status has changed.

#### Rejection Details (`/rejection`)
- Show rejection message from admin (if provided).
- "Edit & Resubmit" button → navigates to Edit Profile. Editing any field while rejected auto-resubmits (status flips back to `pending_call` server-side) — there's no separate "resubmit" action.

#### Home (`/home`)
- Welcome message with caregiver's name.
- **Green verified icon** displayed prominently (indicates verified status).
- Quick stats/info:
  - Status badge (Available / Assigned) with green icon for verified.
- Jobs section: List of active job postings with Apply / Reject buttons.
- Navigation to: Profile, Jobs, Settings.

#### Jobs Dashboard (`/jobs`)
- List of all active job postings AND active NurseNow Organisation requirements (`GET
  /caregiver/organisation-requirements`), **merged into one list, sorted by post date (newest
  first)** — not a separate tab. (An earlier iteration gave organisation requirements their own
  4th "Organisation Openings" bottom-nav tab, a deliberate separate-section decision; reversed on
  explicit follow-up request so a caregiver only has to check one place.)
- Each job card shows: Duty Type + City, Area, Language/Gender/Religion preference tags, Description.
- Each organisation requirement card shows the posting org's name/type/city/area, Type of Nurse,
  Accommodation/Food, Special Skills, and (once admin-approved) Frequency of Care/Salary/Schedule
  (the same red blinking urgency badge jobs use for Preferred Start Date, showing a date range or
  a list of specific days via `organisationScheduleLabel()` — see CLAUDE.md's "Schedule Type") —
  a visually distinct card from a job card (they share no fields worth unifying), just
  interleaved in the same scrollable list.
- Action buttons per job/requirement: **Apply**, **Reject** (same `POST .../:id/apply` mechanic
  either way, dispatched to the right endpoint per item's type).
- Already-applied jobs/requirements show the application status ("You applied" / "You declined" /
  "You were accepted") instead of buttons — for a requirement this needs `GET
  /caregiver/organisation-requirements`'s per-caregiver `my_application` join (added for this
  merge; the endpoint never returned it while Organisation Openings was its own tab).
- Pull-to-refresh for new jobs/requirements.
- Gear icon (`Icons.tune`) in the app bar → Job Search Preferences screen (preferred city, preferred shift/duty type, minimum salary per day/month — all dynamically filter this list, see `GET /caregiver/jobs` in 6.5). This only filters jobs, not organisation requirements (no preference-based filtering exists for those yet). Saving pops back here and immediately reloads the list.

#### Profile View (`/profile`)
- Display all profile information (read-only).
- "Edit" button.

#### Edit Profile (`/profile/edit`)
- Editable: Age, Languages, Highest Qualification — one "Save" button for this section. Preferred City moved to the Jobs tab's gear icon (see Job Search Preferences below) along with the other job-search-only preferences — this screen's info banner points there.
- Full Name, Gender, and Religion shown read-only — contact the office to change any of them; only admins can.
- Phone Number: own input + "Save" button (re-verification sensitive — see below).
- Login PIN: own input + "Save" button.
- Document upload/re-upload: Selfie, Aadhaar, Qualification Document, Other Documents — each uploads immediately on pick, individually.
- Info banner: "Changes will be reviewed by admin. Your current verification status is not affected." — except changing Phone Number or re-uploading Aadhaar, which is flagged as identity-sensitive and (for `available`/`unavailable`/`rejected`) resets status to `pending_call` for re-verification.
- If current status is `rejected`, any other edit (age, languages, qualification, selfie, qualification/other documents, login PIN) also resets status to `pending_call` automatically — no separate resubmit action.

#### Job Search Preferences (pushed from the Jobs tab's gear icon, not a bottom-nav destination)
- Editable: Preferred City (multi-select), Preferred Shift/Duty Type (multi-select), Minimum Salary — ₹/day (optional), Minimum Salary — ₹/month (optional) — one "Save" button.
- Info banner: these only control which jobs show up on the Jobs tab — no admin approval needed, never affects verification status.
- All four fields go through the same `PATCH /caregiver/profile` self-edit endpoint as Edit Profile (see 6.4) — same partial-write semantics, `has_pending_edits` flagged, `verification_status` untouched except the `rejected` auto-resubmit rule.
- On successful save, pops back to the Jobs tab, which immediately re-fetches `GET /caregiver/jobs` so the new filtering is visible right away.

#### Settings (`/settings`)
- Change code (4-digit PIN update).
- Logout button.
- App version.

### 12.4 Navigation Rules

**DO NOT:**
- Show bottom navigation bar at all times after registration (including pending statuses). Seeing jobs motivates caregivers to complete onboarding. 3 tabs: Profile, Jobs (also lists NurseNow Organisation-posted requirements, merged in — see 12.3 and 6.11), MyJobs (the caregiver's own assigned/completed jobs AND organisation requirements together — see `GET /caregiver/jobs/assigned` and `GET /caregiver/organisation-requirements/assigned`).
- Do NOT allow back navigation from Pending Call to Registration (registration is complete).

---

### 12.5 NurseNow App — Screens & Navigation

Separate Flutter app (`apps/nursenow-app`), not a tab/mode inside the caregiver app — see
"NurseNow" in CLAUDE.md. **Both account types are built**: Individual (patient/family), and
Organisation (hospital/rehab/clinic) — a genuinely different account type sharing only the
Login/Splash flow and the registration screen's phone/PIN prefix, then branching to its own
home route, posting screen, and requirement shape (6.11).

| Screen Name | Route | Access Condition |
|-------------|-------|-------------------|
| Splash | `/` | Always (app launch) |
| Login | `/login` | Unauthenticated — phone + 4-digit code (same mechanic as caregiver-app) |
| Registration | `/register` | Unauthenticated — phone → PIN → full name → account-type selector (Individual / Organisation). Choosing Organisation reveals `organisation_name`, `organisation_type` (dropdown: Hospital/Rehab/Clinic), `city` (dropdown, incl. Others), and `area` fields in place of the Individual branch's plain full-name field |
| Jobs Posted | `/home` | Authenticated as Individual — bottom nav tab 2 |
| Profile | `/profile` | Authenticated as Individual — bottom nav tab 1 |
| Post Requirement | `/post-requirement` | Authenticated as Individual, no live requirement, not `is_job_posting_blocked` |
| Requirements Posted | `/org-home` | Authenticated as Organisation — sole top-level screen (no bottom nav) |
| Post Organisation Requirement | `/org-post-requirement` | Authenticated as Organisation, not `is_job_posting_blocked` (no live-requirement limit, unlike Individual) |

There is no status-gated routing like the caregiver app's `verification_status` for either
account type — neither has a verification pipeline, just the two independent block levers
(job-posting block, full block) described in the NurseNow section of CLAUDE.md. Since the
shared `POST /auth/login/code` response doesn't indicate role, post-login routing decodes the
role client-side from the JWT (`core/jwt_decode.dart`'s `decodeJwtPayload()`, a base64url decode
of the token's middle segment, no signature verification — purely to pick a home route); decode
failure falls back to Individual for backward compatibility. An Individual session gets the
2-tab bottom nav below; an **Organisation session has no bottom nav at all** — `/org-home` is
its sole top-level screen, reached directly after login/registration.

Once authenticated as Individual, a 2-tab bottom nav (`NurseNowBottomNav`, mirroring NurseJobs'
`CaregiverBottomNav`) is shown on both top-level screens — Profile and Jobs Posted — switching
tabs via `pushReplacementNamed`, not a stack push.

**Profile screen**: account identity (name, phone), a job-posting-blocked notice if applicable,
independently-saved Phone Number and Login PIN sections (`PATCH /individual/profile/phone` /
`/code`, 6.10 — neither ever triggers a re-review reset, unlike the caregiver equivalent), and
Logout.

**Jobs Posted screen**: the account's **full requirement history** (`GET /individual/requirements`,
6.10) — every past posting, not just the current one, newest first. Each card renders the full
About Patient / About Nurse-Caregiver Requirement detail inline (including the free-text
description) and, for every requirement past `pending_review`, an applicants section: the total
applicant count up front, then a **forced one-at-a-time review** of undecided (`applied`)
candidates — only the single oldest-undecided candidate is shown, with Accept/Reject, and the next
one isn't revealed until this one is decided. **Rejecting requires a reason** — the dialog's
Confirm button stays disabled until non-empty text is entered, matching the server-side `JOB_012`
backstop (6.10). Already-decided candidates (from this session or earlier) remain visible below in
a read-only list, including the accepted one's name/phone and any stored decline reasons — this
history is shown regardless of the requirement's current status, so it stays visible even after
the requirement closes. A "Post a Requirement" CTA is shown whenever the account has **no live
requirement** (none `pending_review` or `active`) — not merely whenever the history is empty, so
posting again is always available once the current one closes or is rejected; `JOB_009`
server-side is the backstop, the UI computes the same live/not-live signal client-side from the
fetched list.

**Post Requirement and Registration screens use the same mandatory-field validation UX as
admin-web's job-posting form** (13.3's `AdminJobsScreen`): submit is always tappable; on a missing
mandatory field it flags every missing one red (inline error text) and scrolls/focuses straight to
the first invalid field, rather than a single generic error message.

**Requirements Posted screen (`/org-home`, Organisation)**: an always-postable list — **no
live-limit banner**, unlike Individual's Jobs Posted screen, since Organisation has no
one-live-requirement rule. Renders `GET /organisation/requirements` (6.11), the account's full
requirement history newest-first, each card showing Type of Nurse, Accommodation/Food, Special
Skills, and (once past `pending_review`) Frequency of Care/Salary/Schedule (date range or
specific days, via `organisationScheduleLabel()`) once admin sets them. Applicant review here is
the **simple non-forced Accept/Reject** described in
6.11 — a free list with an optional reason, not Individual's forced one-at-a-time/
mandatory-reason flow. A "Post a Requirement" CTA is always visible (no live/not-live gating).

**Post Organisation Requirement screen (`/org-post-requirement`)**: the "exclusive" org form —
Type of Nurse dropdown (7 values), Accommodation Provided / Food Provided Yes-No toggles, and
an optional Special Skills free-text field. **No About Patient / Job Location sections at all**
— city/area are inherited from the org's own registration, and there's no `care_receiver` for an
organisation requirement. Same always-tappable-submit / highlight-and-scroll validation pattern
as every other NurseNow form.

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
| 8 | App Versions | `/app-versions` | Admin, Super Admin |
| 9 | Patients/Family | `/patients-family` | Admin, Super Admin |
| 10 | Rehab/Hospitals | `/rehab-hospitals` | Admin, Super Admin |
| 11 | Organisation Requirements | `/rehab-requirements` | Admin, Super Admin |

### 13.2 Navigation Structure

**Sidebar Navigation:**
- Dashboard (icon: grid)
- Caregivers (icon: people)
- Patients/Family (icon: family_restroom) — NurseNow individual accounts; list + block/unblock, see "NurseNow" in CLAUDE.md and 6.10
- Jobs (icon: work) — also surfaces NurseNow's `pending_review` postings (Pending Review badge, Reject action, poster name) inline, no separate queue
- Rehab/Hospitals (`OrganisationsListScreen`) — NurseNow organisation (hospital/rehab/clinic) accounts; mirrors Patients/Family exactly — list + block/unblock at either level (`job_posting`/`full`), see "NurseNow" in CLAUDE.md and 6.11
- Organisation Requirements (`AdminOrganisationRequirementsScreen`) — every organisation-posted requirement, deliberately **not** folded into the Jobs tab (a wholly separate table/model, see 6.11): Applicants (a Profile button per applicant — links to the same `/caregiver-detail` full admin screen the Jobs tab's own Applicants dialog already uses, no new backend endpoint needed for the admin case — plus Accept/Reject per applicant, optional reason), Reject (pending_review only, reason-required dialog), and a single Edit action (dialog collecting Frequency of Care/Salary and a required Schedule — `SegmentedButton` for Date Range vs Specific Days; Date Range shows a start/end date pair, Specific Days reveals a nested Weekly/Monthly `SegmentedButton` in turn showing either 7 weekday chips or a real month-grid calendar, with a green checkmark on every already-picked value) that doubles as "Approve" from pending_review and as an ordinary edit from active/closed — admin can revisit/correct these fields later, not just once at approval. Tapping a row opens a read-only detail view first, with its own Edit button — same pattern as the Jobs tab below
- Audit Logs (icon: clipboard)
- Admin Management (icon: shield) — only visible to Super Admin
- App Versions (icon: system_update) — sets the force-upgrade minimum version per platform, see 6.9
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
- Columns: Name, Phone, Gender, Age, Qualification, Status, Registered.
- Filter panel (collapsible):
  - Search (text)
  - Status (dropdown)
  - Qualification (dropdown)
  - Language (multi-select)
  - Date range (from/to pickers)
- Quick filter chips: Last 24h, Last 7d, Last 30d.
- Click row → navigate to Caregiver Detail.
- Real-time: new rows appear automatically, status badges update live.

#### Caregiver Detail (`/caregivers/:id`)
- **Header:** Name, phone, status badge, registration date.
- **Tabs:**
  - Profile: All profile fields displayed.
  - Documents: Inline preview (image viewer / PDF viewer). Download button.
  - Notes: Admin notes form (internal notes, availability remarks). Save button.
  - Audit History: Filtered audit log for this caregiver.
- **Action buttons (based on status):**
  - `pending_call` → "Approve" (→ available), "Reject" buttons. Admin reviews the full profile (all fields collected at registration) and approves in one step — there's no separate call-verification step.
  - `available` / `unavailable` / `assigned` / `rejected` → No status actions (status override endpoint can still force any transition, but the quick-action buttons only surface from `pending_call`).
- **Reject modal:** Text input for rejection message (optional), Confirm button.
- **Change Phone button:** Opens modal with new phone number input. For account recovery.

#### Audit Logs (`/audit-logs`)
- Data table: Timestamp, Actor, Action, Entity, Job, Target, Before, After, IP.
- The Job column renders the job's display id ("ADMIN-JOB-<n>"/"PAT-JOB-<n>", from the resolved `admin_job_number`/`patient_job_number`, see 6.8) as a link for any job-related entry — tapping it opens that job's applicants dialog (`JobDetailDialog`, fetched fresh by id, independent of whatever page the Jobs list happens to be on). Every other entry shows "-".
- Filters: Action type, date range (target_user_id is settable via the caregiver detail screen's "view audit history" link).
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
| Address | Max 500 chars |
| Code | Exactly 4 digits, numeric |
| File size | Max 10MB |
| Other documents | Max 3 files |
| Rejection message | Max 1000 chars |
| Preferred City | Valid city enum value |
| Availability notes | Max 500 chars |

### 15.4 Status Transition Matrix

```
pending_call ──────────────→ available (admin: approve — sets verified_at, green icon)
pending_call ──────────────→ rejected (admin: status endpoint)
available ─────────────────→ unavailable (caregiver OR admin: "not taking work right now")
unavailable ───────────────→ available (caregiver OR admin: "ready for work again")
available ─────────────────→ assigned (admin: assign endpoint — only from available, NOT unavailable)
assigned ──────────────────→ available (admin: unassign endpoint — work completed)
available ─────────────────→ pending_call (system: caregiver changed phone / re-uploaded Aadhaar)
unavailable ────────────────→ pending_call (system: caregiver changed phone / re-uploaded Aadhaar)
rejected ──────────────────→ pending_call (system: caregiver edited any profile field — auto-resubmit, no new call needed)
```

The admin status-override endpoint (`PATCH /admin/caregivers/:id/status`) is deliberately
unrestricted: it accepts any of the 5 statuses as a target from any current status, bypassing
this matrix. The matrix above documents the *normal* flow driven by caregiver actions and
system triggers.

### 15.5 Naming Conventions

| Context | Convention | Example |
|---------|-----------|---------|
| Database tables | snake_case | `caregiver_profiles` |
| Database columns | snake_case | `verification_status` |
| API endpoints | kebab-case | `/admin/caregivers/:id/status` |
| API request/response fields | snake_case | `full_name`, `verification_status` |
| NestJS files | kebab-case | `caregiver.controller.ts` |
| NestJS classes | PascalCase | `CaregiverController` |
| Flutter files | snake_case | `caregiver_profile_screen.dart` |
| Flutter classes | PascalCase | `CaregiverProfileScreen` |
| Flutter routes | kebab-case | `/pending-call` |
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
