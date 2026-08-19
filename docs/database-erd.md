# VitaCare Database Entity-Relationship Diagram

## ASCII Diagram

```
┌──────────────────────┐
│       users          │
│──────────────────────│
│ id (PK)              │
│ email                │
│ phone                │
│ password_hash        │
│ code_hash            │
│ full_name            │
│ role                 │  ◄── super_admin | admin | caregiver |
│                      │      individual | organisation
│ is_active            │
│ fcm_token            │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
     ┌─────┼──────────────────────────────────┬───────────┐
     │     │                                  │           │
     │     │ N                                │ N         │ N
     │     ▼                                  ▼           ▼
     │  ┌──────────────────────┐  ┌──────────────────────┐ ┌──────────────────────┐
     │  │   refresh_tokens     │  │     audit_logs        │ │  individual_profiles │
     │  │──────────────────────│  │──────────────────────│ │──────────────────────│
     │  │ id (PK)              │  │ id (PK)              │ │ id (PK)              │
     │  │ user_id (FK→users)   │  │ user_id (FK→users)   │ │ user_id (FK→users)   │
     │  │ token_hash           │  │ target_user_id       │ │   ◄── 1:1 with users │
     │  │ expires_at           │  │   (FK→users)         │ │ is_job_posting_      │
     │  │ created_at           │  │ action               │ │   blocked            │
     │  │ revoked_at           │  │ entity_type          │ │ block_reason         │
     │  └──────────────────────┘  │ entity_id            │ │ created_at           │
     │                            │ before_value         │ │ updated_at           │
     │                            │ after_value          │ └──────────────────────┘
     │ 1                          │ ip_address           │  ◄── NurseNow (patient/
     ▼                            │ created_at           │      family) accounts;
┌──────────────────────┐          └──────────────────────┘      role = 'individual'
│  caregiver_profiles  │
│──────────────────────│
│ id (PK)              │
│ user_id (FK→users)   │  ◄── 1:1 with users
│ selfie_photo_url     │
│ gender               │
│ age                  │
│ highest_qualification│
│ religion             │  ◄── set at registration, locked
│ qualification_doc_url│
│ aadhaar_document_url │
│ other_document_urls  │
│ terms_accepted       │
│ verification_status  │
│ rejection_message    │
│ has_pending_edits    │
│ verified_at          │
│ verified_by (FK→users)│
│ min_salary_per_day   │  ◄── job search preference, nullable
│ min_salary_per_month │  ◄── job search preference, nullable
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
     ┌─────┼──────────────────────────────────────┐
     │     │                     │                 │
     │ N   │ N                   │ N               │ 1
     ▼     ▼                     ▼                 ▼
┌────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐  ┌──────────────────┐
│ caregiver_     │  │ caregiver_preferred_   │  │ caregiver_preferred_   │  │   admin_notes    │
│ languages      │  │ cities                 │  │ duty_types             │  │──────────────────│
│────────────────│  │────────────────────────│  │────────────────────────│  │ id (PK)          │
│ id (PK)        │  │ id (PK)                │  │ id (PK)                │  │ profile_id       │
│ profile_id     │  │ profile_id (FK→profiles)│  │ profile_id (FK→profiles)│  │   (FK→profiles)  │
│   (FK→profiles)│  │ city                   │  │ duty_type              │  │ admin_id         │
│ language       │  └────────────────────────┘  └────────────────────────┘  │   (FK→users)     │
└────────────────┘                                                         │ internal_notes   │
                                                                            │ availability_    │
                                                                            │   remarks        │
                                                                            │ created_at       │
                                                                            │ updated_at       │
                                                                            └──────────────────┘
```

`min_salary_per_day`/`min_salary_per_month` and `caregiver_preferred_cities`/
`caregiver_preferred_duty_types` are job search preferences — they
dynamically filter `GET /caregiver/jobs`, are editable anytime via the
self-edit endpoint, and never affect `verification_status`. A `daily` job's
`salary_amount` is only ever compared against `min_salary_per_day`, never
`min_salary_per_month`, and vice versa.

Admin-assigned work types, service modes, and salary (formerly
`caregiver_work_types` / `caregiver_service_modes` tables plus a
`caregiver_profiles.salary` column) have been removed from the product
entirely, along with `admin_notes.rate_24hrs_live_in` /
`rate_12hrs_pg`. `WorkType`/`ServiceMode`/`SalaryRanges` are gone entirely —
job postings are no longer built around a "work type" category; see
`care_receivers` and the redesigned `jobs` below.

```
┌──────────────────────┐
│    care_receivers    │  ◄── "About Patient" in admin-web UI
│──────────────────────│
│ id (PK)              │
│ age                  │
│ gender               │
│ weight_kg            │
│ mobility             │
│ communication        │
│ feeding_type         │
│ medical_assistance   │  ◄── JSONB array
│ has_medical_condition│
│ medical_conditions   │  ◄── JSONB array
│ medical_condition_   │  ◄── free text, shown when medical_conditions
│   other              │      includes 'other'
│ toilet_assistance    │  ◄── JSONB array (multi-select)
│ toilet_assistance_   │  ◄── free text, shown when toilet_assistance
│   other              │      includes 'others'
│ requires_vital_      │
│   monitoring         │
│ vital_monitoring_    │  ◄── JSONB array
│   types              │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │ 1
           │
           │ 1
           ▼
┌──────────────────────┐
│         jobs          │
│──────────────────────│
│ id (PK)              │
│ job_number            │  ◄── SERIAL, shown as "Job #<n>" everywhere
│ care_receiver_id     │
│   (FK→care_receivers)│
│ city                 │
│ area                 │  ◄── free text, required via API (was optional)
│ description          │
│ duty_type            │  ◄── 3 fixed shifts only; UI label "Hours Care Needed"
│ frequency_of_care    │  ◄── daily/monthly; NULL while pending_review
│ start_time           │  ◄── derived from duty_type
│ end_time             │  ◄── derived from duty_type
│ start_date           │  ◄── UI label "Preferred Start Date"
│ languages            │  ◄── JSONB array, multi-select
│ salary_amount        │  ◄── ₹/day or ₹/month per frequency_of_care; NULL while pending_review
│ preferred_gender     │  ◄── NULL = no preference
│ preferred_religion   │  ◄── NULL = no pref; "others" excluded
│ status               │  ◄── pending_review | active | closed
│ rejection_reason     │  ◄── set only on admin reject of a pending_review row
│ posted_by (FK→users) │  ◄── an admin OR a NurseNow individual (role='individual')
│ posted_at            │  ◄── drives 3-day apply-by urgency window
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
           │ N
           ▼
┌──────────────────────┐
│   job_applications    │
│──────────────────────│
│ id (PK)              │
│ job_id (FK→jobs)     │
│ profile_id           │
│   (FK→profiles)      │
│ status               │  ◄── applied | rejected | accepted
│ decided_by (FK→users)│  ◄── set only by an admin decision (not caregiver self-action)
│ applied_at           │  ◄── null if declined without ever applying
│ accepted_at          │  ◄── set only when an admin accepts
│ rejected_at          │  ◄── self-decline OR admin reject/undo-accept
│ created_at           │
│ updated_at           │
└──────────────────────┘
```

`care_receivers` is 1:1 with a `jobs` row today (created together, no
independent reuse/search screen) — structured as its own table rather than
embedded columns on `jobs` to leave a clean seam for a future "Patient" app
to supply real care-receiver identity data. Accepting a `job_applications`
row (admin action) closes the job and sets the caregiver's
`verification_status` to `assigned`; rejecting a previously-accepted
application reopens the job and returns the caregiver to `available`.

NurseNow Organisation (hospital/rehab/clinic, `users.role = 'organisation'`) hangs off `users`
independently from `caregiver_profiles`/`jobs` above — deliberately **not** built on the jobs/
care_receivers/job_applications tables the way NurseNow Individual is (see "NurseNow" in
CLAUDE.md for why). `organisation_profiles` mirrors `individual_profiles`' shape (no
verification pipeline, same two block levers) plus registration-collected identity/location
that every one of the org's requirements inherits — there is no per-requirement `city`/`area`.

```
┌──────────────────────┐
│ organisation_profiles │  ◄── NurseNow (hospital/rehab/clinic)
│──────────────────────│      accounts; role = 'organisation'
│ id (PK)              │
│ user_id (FK→users)   │  ◄── 1:1 with users
│ organisation_name    │
│ contact_person_name  │
│ organisation_type    │  ◄── hospital | rehab | clinic
│ city                 │  ◄── org's own registered location;
│ area                 │      every requirement inherits this
│                      │      (no per-requirement city/area)
│ is_job_posting_      │
│   blocked            │
│ block_reason         │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
           │ N
           ▼
┌──────────────────────┐
│  organisation_        │
│    requirements       │  ◄── NOT a jobs row — separate table/codepath,
│──────────────────────│      no care_receiver, no one-live-requirement limit
│ id (PK)              │
│ requirement_number   │  ◄── SERIAL, "Requirement #<n>"-style short id
│ posted_by (FK→users) │  ◄── always role='organisation'
│ type_of_nurse        │  ◄── 7-value enum; distinct from Qualification
│ frequency_of_care    │  ◄── daily/monthly; NULL until admin approves
│ salary_amount        │  ◄── NULL until admin approves
│ schedule_type        │  ◄── date_range | specific_days; NULL until admin approves;
│                       │      replaces start_date-only design entirely (migration 043)
│ start_date           │  ◄── only set when schedule_type='date_range'
│ end_date             │  ◄── only set when schedule_type='date_range'
│ specific_days        │  ◄── INTEGER[]; only set when schedule_type='specific_days'
│ accommodation_       │
│   provided           │
│ food_provided        │
│ special_skills       │
│ status               │  ◄── pending_review | active | closed
│ rejection_reason     │  ◄── set only on admin reject of a pending_review row
│ posted_at            │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
           │ N
           ▼
┌──────────────────────┐
│  organisation_        │
│    requirement_       │
│    applications       │
│──────────────────────│
│ id (PK)              │
│ requirement_id       │
│   (FK→organisation_  │
│    requirements)     │
│ profile_id           │
│   (FK→caregiver_     │
│    profiles)         │
│ status               │  ◄── applied | rejected | accepted | completed
│ decided_by (FK→users)│  ◄── org or admin who accepted/rejected
│ applied_at           │
│ accepted_at          │
│ rejected_at          │
│ completed_at         │
│ decline_reason       │  ◄── optional (unlike Individual's mandatory rule)
│ created_at           │
│ updated_at           │
└──────────────────────┘
```

Shaped identically to `jobs`/`job_applications` (same 3 status values, same 4 application
states, `decline_reason` from day one) but on entirely separate tables — an org's requirement is
never a foreign key into `jobs`. Accepting an `organisation_requirement_applications` row closes
the requirement and sets the caregiver's `verification_status` to `assigned`; rejecting a
previously-accepted application reopens the requirement and returns the caregiver to
`available` — the exact same state-machine side effects as `job_applications`, since both share
`caregiver_profiles.verification_status` (a caregiver already `assigned` to a job can still be
accepted onto an organisation requirement, and vice versa).

```
┌──────────────────────┐
│   app_min_versions    │  ◄── force-upgrade: 2-row singleton, one per platform
│──────────────────────│
│ platform (PK)         │  ◄── 'android' | 'ios'
│ min_version           │  ◄── seeded '1.0.0'; caregiver app blocks below this
│ store_url             │
│ update_message        │
│ updated_by (FK→users) │  ◄── admin who last changed this row; NULL until first edit
│ updated_at            │
└──────────────────────┘
```

Not part of the caregiver-profile/jobs graph above — a standalone admin
control checked by the caregiver app on every cold launch (`GET
/app-versions/check`, public, no auth) before anything else loads. See
SPEC.md 6.9.

## Relationships

| Table A | Table B | Type | FK Column | Notes |
|---------|---------|------|-----------|-------|
| users | caregiver_profiles | 1:1 | caregiver_profiles.user_id | Each caregiver has exactly one profile |
| users | individual_profiles | 1:1 | individual_profiles.user_id | Each NurseNow individual (role='individual') has exactly one profile |
| users | organisation_profiles | 1:1 | organisation_profiles.user_id | Each NurseNow organisation (role='organisation') has exactly one profile |
| users | refresh_tokens | 1:N | refresh_tokens.user_id | A user can have multiple active/revoked tokens |
| users | audit_logs (actor) | 1:N | audit_logs.user_id | Who performed the action |
| users | audit_logs (target) | 1:N | audit_logs.target_user_id | Who was affected by the action |
| users | caregiver_profiles (verified_by) | 1:N | caregiver_profiles.verified_by | Admin who verified the profile |
| users | admin_notes (admin) | 1:N | admin_notes.admin_id | Admin who wrote the notes |
| caregiver_profiles | caregiver_languages | 1:N | caregiver_languages.profile_id | A profile has 1+ languages |
| caregiver_profiles | caregiver_preferred_cities | 1:N | caregiver_preferred_cities.profile_id | A profile has 0+ preferred cities (multi-select) |
| caregiver_profiles | caregiver_preferred_duty_types | 1:N | caregiver_preferred_duty_types.profile_id | A profile has 0+ preferred shift/duty types (multi-select) |
| caregiver_profiles | admin_notes | 1:1 | admin_notes.profile_id | One notes record per profile (upserted) |
| users | jobs (posted_by) | 1:N | jobs.posted_by | Admin, or a NurseNow individual (role='individual'), who posted the job |
| care_receivers | jobs | 1:1 | jobs.care_receiver_id | Each job describes exactly one care receiver's needs |
| jobs | job_applications | 1:N | job_applications.job_id | Caregiver applications to a job |
| caregiver_profiles | job_applications | 1:N | job_applications.profile_id | A caregiver's applications across jobs |
| users | job_applications (decided_by) | 1:N | job_applications.decided_by | Admin who accepted/rejected the application |
| users | app_min_versions (updated_by) | 1:N | app_min_versions.updated_by | Admin who last set this platform's minimum version |
| users | organisation_requirements (posted_by) | 1:N | organisation_requirements.posted_by | The organisation account that posted the requirement |
| organisation_requirements | organisation_requirement_applications | 1:N | organisation_requirement_applications.requirement_id | Caregiver applications to an organisation requirement |
| caregiver_profiles | organisation_requirement_applications | 1:N | organisation_requirement_applications.profile_id | A caregiver's applications across organisation requirements |
| users | organisation_requirement_applications (decided_by) | 1:N | organisation_requirement_applications.decided_by | Org (or admin) who accepted/rejected the application |

## Table Descriptions

| Table | Purpose |
|-------|---------|
| **users** | Core identity table for all user types (caregivers, admins, super_admins, NurseNow individuals, and NurseNow organisations). Holds auth credentials, contact info, role, and FCM token for push notifications. |
| **refresh_tokens** | Stores hashed refresh tokens for JWT rotation. Each token use generates a new one and revokes the old. Supports 30-day TTL. |
| **caregiver_profiles** | Full onboarding profile for caregivers, collected in one registration call, including document URLs and verification workflow state (`pending_call`, `available`, `unavailable`, `assigned`, `rejected`). Central to the verification pipeline. Also carries `min_salary_per_day`/`min_salary_per_month` — job search preferences that dynamically filter `GET /caregiver/jobs`, editable anytime, never affecting verification status. |
| **individual_profiles** | Role-specific data for a NurseNow patient/family account (`users.role = 'individual'`). No verification pipeline — just two independent admin block levers: `is_job_posting_blocked` (blocks new postings only) and the shared `users.is_active` (full login lockout), each with an admin-entered `block_reason`. See "NurseNow" in CLAUDE.md. |
| **organisation_profiles** | Role-specific data for a NurseNow hospital/rehab/clinic account (`users.role = 'organisation'`). Mirrors `individual_profiles`' two block levers, plus registration-collected `organisation_name`/`contact_person_name`/`organisation_type`/`city`/`area` — every requirement the org posts inherits this location, since there's no per-requirement city/area. See "NurseNow" in CLAUDE.md. |
| **caregiver_languages** | Junction table for languages a caregiver speaks. Constrained to a fixed enum of 9 Indian languages. |
| **caregiver_preferred_duty_types** | Junction table for a caregiver's preferred shift/duty types (job search preference, multi-select from the same 3 fixed shifts as a job's `duty_type`). Same pattern as `caregiver_preferred_cities`. Dynamically filters `GET /caregiver/jobs`; editable anytime via the self-edit endpoint. |
| **admin_notes** | Internal-only notes attached to a caregiver profile. Never exposed to caregivers. Upserted per profile. |
| **care_receivers** | "About Patient" in the admin-web UI. Care-needs description (age, gender, weight, mobility, communication, feeding, toilet assistance, medical assistance/conditions, vital monitoring) for the person a job is posted for. 1:1 with a job; no full patient PII/identity record yet — a future "Patient" app is expected to eventually supply that. |
| **jobs** | Job listings sent to all caregivers as push notifications — posted either by an admin (straight to `active`) or by a NurseNow individual (`POST /individual/requirements`, created `pending_review` with `frequency_of_care`/`salary_amount` null until admin approves-by-editing, or declines via `PATCH /admin/jobs/:id/reject` with `rejection_reason`). Built around the linked care receiver's needs plus location, duty type (one of 3 fixed shifts, with derived timings), a required salary, and multi-select language / gender / religion (`others` excluded) *preferences* (not eligibility filters). Has a short human-friendly `job_number` distinct from its UUID `id`, and a `posted_at` timestamp (separate from immutable `created_at`) that drives a caregiver-facing 3-day apply-by urgency window — `posted_at` restarts on repost/approval (editing a closed or pending_review job to active), not on a plain edit. |
| **job_applications** | Caregiver applications (applied/rejected) to job postings, and the admin's accept/reject decision on each. One application per caregiver per job. Accepting closes the job and assigns the caregiver; rejecting a prior acceptance reopens the job. |
| **organisation_requirements** | An organisation's posted requirement — deliberately not a `jobs` row (separate table/codepath, see "NurseNow" in CLAUDE.md). No `care_receiver`, no `city`/`area`/`duty_type` (inherited from the posting org's `organisation_profiles` row). Posted by an admin/super_admin edit-to-approve, same `pending_review → active → closed` lifecycle as `jobs`, but with **no one-live-requirement limit** (an org can have many simultaneous postings). Has its own short `requirement_number` and `posted_at` (same repost-on-approval semantics as `jobs.posted_at`). |
| **organisation_requirement_applications** | Caregiver applications to an organisation requirement — a separate table from `job_applications`, shaped identically (including `completed` status and `decline_reason` from day one). Accepting closes the requirement and assigns the caregiver; rejecting a prior acceptance reopens it — sharing `caregiver_profiles.verification_status` with the regular jobs pipeline. |
| **app_min_versions** | Force-upgrade config: one row per platform (`android`/`ios`), admin-editable. The caregiver app checks this on every launch and blocks with an "Update Required" screen if its installed build is below `min_version`. |
| **audit_logs** | Immutable append-only log of all significant actions (registrations, status changes, edits, admin actions). Used for compliance and debugging. `GET /admin/audit-logs` additionally resolves `job_number`/`job_id` at query time (not stored columns) for job-related entries — see SPEC.md 6.8. |
