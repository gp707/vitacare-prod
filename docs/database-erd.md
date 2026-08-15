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
│ salary               │
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
     ┌─────┼─────────────────────┬─────────────────────┐
     │     │                     │                     │
     │ N   │ N                   │ N                   │ 1
     ▼     ▼                     ▼                     ▼
┌────────────────┐  ┌──────────────────────┐  ┌──────────────────┐
│ caregiver_     │  │ caregiver_           │  │   admin_notes    │
│ languages      │  │ service_modes        │  │──────────────────│
│────────────────│  │──────────────────────│  │ id (PK)          │
│ id (PK)        │  │ id (PK)              │  │ profile_id       │
│ profile_id     │  │ profile_id           │  │   (FK→profiles)  │
│   (FK→profiles)│  │   (FK→profiles)      │  │ admin_id         │
│ language       │  │ service_mode         │  │   (FK→users)     │
└────────────────┘  └──────────────────────┘  │ internal_notes   │

┌────────────────────────┐
│ caregiver_preferred_   │
│ cities                 │
│────────────────────────│
│ id (PK)                │
│ profile_id (FK→profiles)│
│ city                   │
└────────────────────────┘
(Also N from caregiver_profiles — multi-select preferred cities,
same 1:N junction-table pattern as caregiver_languages.)

                                              │ rate_24hrs_live_in│
                                              │ rate_12hrs_pg    │
                                              │ availability_    │
                                              │   remarks        │
                                              │ created_at       │
                                              │ updated_at       │
                                              └──────────────────┘

     │ service_mode         │         ┌──────────────────────┐
     └──────────────────────┘         │ caregiver_           │
           ▲                          │ work_types           │
           │ N                        │──────────────────────│
           │                          │ id (PK)              │
    (FK from caregiver_profiles)      │ profile_id           │
                                      │   (FK→profiles)      │
                                      │ work_type            │
                                      │ assigned_by          │
                                      │   (FK→users)         │
                                      │ assigned_at          │
                                      └──────────────────────┘
```

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
| caregiver_profiles | caregiver_service_modes | 1:N | caregiver_service_modes.profile_id | A profile has 1+ service modes |
| caregiver_profiles | caregiver_work_types | 1:N | caregiver_work_types.profile_id | Admin-assigned work types (read-only for caregiver) |
| users | caregiver_work_types (assigned_by) | 1:N | caregiver_work_types.assigned_by | Admin who assigned the work type |
| caregiver_profiles | admin_notes | 1:1 | admin_notes.profile_id | One notes record per profile (upserted) |
| users | jobs (posted_by) | 1:N | jobs.posted_by | Admin who posted the job |
| jobs | job_responses | 1:N | job_responses.job_id | Caregiver responses to a job |
| caregiver_profiles | job_responses | 1:N | job_responses.profile_id | A caregiver's responses across jobs |

## Table Descriptions

| Table | Purpose |
|-------|---------|
| **users** | Core identity table for all user types (caregivers, admins, super_admins). Holds auth credentials, contact info, role, and FCM token for push notifications. |
| **refresh_tokens** | Stores hashed refresh tokens for JWT rotation. Each token use generates a new one and revokes the old. Supports 30-day TTL. |
| **caregiver_profiles** | Full onboarding profile for caregivers, collected in one registration call, including document URLs and verification workflow state (`pending_call`, `available`, `unavailable`, `assigned`, `rejected`). Central to the verification pipeline. |
| **caregiver_languages** | Junction table for languages a caregiver speaks. Constrained to a fixed enum of 9 Indian languages. |
| **caregiver_service_modes** | Junction table for service delivery modes: 24Hrs (Live-In) or 12Hrs (nearby PG). |
| **caregiver_work_types** | Admin-assigned work categories: companion care, bedside care, critical care. Caregivers can view but not modify. |
| **admin_notes** | Internal-only notes and rate information attached to a caregiver profile. Never exposed to caregivers. Upserted per profile. |
| **jobs** | Admin-posted job listings sent to all caregivers as push notifications. Contains work type, city, description, duty timings, language, gender, religion requirements. |
| **job_responses** | Caregiver responses (accept/reject/more_details) to job postings. One response per caregiver per job. |
| **audit_logs** | Immutable append-only log of all significant actions (registrations, status changes, edits, admin actions). Used for compliance and debugging. |
