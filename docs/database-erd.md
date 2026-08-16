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
│ role                 │
│ is_active            │
│ fcm_token            │
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
     ┌─────┼──────────────────────────────────────────┐
     │     │                                          │
     │     │ N                                        │ N
     │     ▼                                          ▼
     │  ┌──────────────────────┐           ┌──────────────────────┐
     │  │   refresh_tokens     │           │     audit_logs        │
     │  │──────────────────────│           │──────────────────────│
     │  │ id (PK)              │           │ id (PK)              │
     │  │ user_id (FK→users)   │           │ user_id (FK→users)   │
     │  │ token_hash           │           │ target_user_id       │
     │  │ expires_at           │           │   (FK→users)         │
     │  │ created_at           │           │ action               │
     │  │ revoked_at           │           │ entity_type          │
     │  └──────────────────────┘           │ entity_id            │
     │                                     │ before_value         │
     │                                     │ after_value          │
     │ 1                                   │ ip_address           │
     ▼                                     │ created_at           │
┌──────────────────────┐                   └──────────────────────┘
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
│ created_at           │
│ updated_at           │
└──────────┬───────────┘
           │
           │ 1
           │
     ┌─────┼─────────────────────┐
     │     │                     │
     │ N   │ N                   │ 1
     ▼     ▼                     ▼
┌────────────────┐  ┌────────────────────────┐  ┌──────────────────┐
│ caregiver_     │  │ caregiver_preferred_   │  │   admin_notes    │
│ languages      │  │ cities                 │  │──────────────────│
│────────────────│  │────────────────────────│  │ id (PK)          │
│ id (PK)        │  │ id (PK)                │  │ profile_id       │
│ profile_id     │  │ profile_id (FK→profiles)│  │   (FK→profiles)  │
│   (FK→profiles)│  │ city                   │  │ admin_id         │
│ language       │  └────────────────────────┘  │   (FK→users)     │
└────────────────┘                              │ internal_notes   │
                                                 │ availability_    │
                                                 │   remarks        │
                                                 │ created_at       │
                                                 │ updated_at       │
                                                 └──────────────────┘
```

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
│ tube_feeding_needs_  │
│   assistance         │
│ medical_assistance   │  ◄── JSONB array
│ has_medical_condition│
│ medical_conditions   │  ◄── JSONB array
│ medical_info         │
│ toilet_assistance    │  ◄── single-select
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
│ area                 │  ◄── free text, optional
│ description          │
│ duty_type            │  ◄── 3 fixed shifts only, no "other"
│ start_time           │  ◄── derived from duty_type
│ end_time             │  ◄── derived from duty_type
│ start_date           │
│ languages            │  ◄── JSONB array, multi-select
│ salary_monthly       │  ◄── ₹/month, highlighted for caregivers
│ preferred_gender     │  ◄── NULL = no preference
│ preferred_religion   │  ◄── NULL = no pref; "others" excluded
│ status               │  ◄── active | closed
│ posted_by (FK→users) │
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
│ decided_by (FK→users)│  ◄── admin who accepted/rejected
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

## Relationships

| Table A | Table B | Type | FK Column | Notes |
|---------|---------|------|-----------|-------|
| users | caregiver_profiles | 1:1 | caregiver_profiles.user_id | Each caregiver has exactly one profile |
| users | refresh_tokens | 1:N | refresh_tokens.user_id | A user can have multiple active/revoked tokens |
| users | audit_logs (actor) | 1:N | audit_logs.user_id | Who performed the action |
| users | audit_logs (target) | 1:N | audit_logs.target_user_id | Who was affected by the action |
| users | caregiver_profiles (verified_by) | 1:N | caregiver_profiles.verified_by | Admin who verified the profile |
| users | admin_notes (admin) | 1:N | admin_notes.admin_id | Admin who wrote the notes |
| caregiver_profiles | caregiver_languages | 1:N | caregiver_languages.profile_id | A profile has 1+ languages |
| caregiver_profiles | caregiver_preferred_cities | 1:N | caregiver_preferred_cities.profile_id | A profile has 0+ preferred cities (multi-select) |
| caregiver_profiles | admin_notes | 1:1 | admin_notes.profile_id | One notes record per profile (upserted) |
| users | jobs (posted_by) | 1:N | jobs.posted_by | Admin who posted the job |
| care_receivers | jobs | 1:1 | jobs.care_receiver_id | Each job describes exactly one care receiver's needs |
| jobs | job_applications | 1:N | job_applications.job_id | Caregiver applications to a job |
| caregiver_profiles | job_applications | 1:N | job_applications.profile_id | A caregiver's applications across jobs |
| users | job_applications (decided_by) | 1:N | job_applications.decided_by | Admin who accepted/rejected the application |

## Table Descriptions

| Table | Purpose |
|-------|---------|
| **users** | Core identity table for all user types (caregivers, admins, super_admins). Holds auth credentials, contact info, role, and FCM token for push notifications. |
| **refresh_tokens** | Stores hashed refresh tokens for JWT rotation. Each token use generates a new one and revokes the old. Supports 30-day TTL. |
| **caregiver_profiles** | Full onboarding profile for caregivers, collected in one registration call, including document URLs and verification workflow state (`pending_call`, `available`, `unavailable`, `assigned`, `rejected`). Central to the verification pipeline. |
| **caregiver_languages** | Junction table for languages a caregiver speaks. Constrained to a fixed enum of 9 Indian languages. |
| **admin_notes** | Internal-only notes attached to a caregiver profile. Never exposed to caregivers. Upserted per profile. |
| **care_receivers** | "About Patient" in the admin-web UI. Care-needs description (age, gender, weight, mobility, communication, feeding, toilet assistance, medical assistance/conditions, vital monitoring) for the person a job is posted for. 1:1 with a job; no full patient PII/identity record yet — a future "Patient" app is expected to eventually supply that. |
| **jobs** | Admin-posted job listings sent to all caregivers as push notifications. Built around the linked care receiver's needs plus location, duty type (one of 3 fixed shifts, with derived timings), a required monthly salary, and multi-select language / gender / religion (`others` excluded) *preferences* (not eligibility filters). Has a short human-friendly `job_number` distinct from its UUID `id`, and a `posted_at` timestamp (separate from immutable `created_at`) that drives a caregiver-facing 3-day apply-by urgency window — `posted_at` restarts on repost (editing a closed job back to active), not on a plain edit. |
| **job_applications** | Caregiver applications (applied/rejected) to job postings, and the admin's accept/reject decision on each. One application per caregiver per job. Accepting closes the job and assigns the caregiver; rejecting a prior acceptance reopens the job. |
| **audit_logs** | Immutable append-only log of all significant actions (registrations, status changes, edits, admin actions). Used for compliance and debugging. |
