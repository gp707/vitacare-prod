# VitaCare Test Plan

## 1. Unit Test Requirements by Module

### Auth Module
- Registration: validates phone format (+91 pattern), rejects duplicates, creates user + profile + languages, returns tokens
- Phone login: returns tokens for existing user, rejects unregistered phone, rejects deactivated accounts
- Email login: validates credentials, rejects wrong password, rejects missing account
- Token refresh: rotates tokens, rejects expired/revoked tokens, revokes old token on use
- Logout: revokes current refresh token
- Forgot password: sends email only if email exists, rejects accounts without email
- Reset password: validates token, rejects expired tokens, updates password_hash

### Caregiver Module
- Profile GET: returns all fields (nulls for unset), generates signed URLs for documents
- Basic profile update: validates age (18-65), languages enum; rejects full_name/gender (locked, admin-only past registration); sets has_pending_edits=true
- Advanced details submit: enforces call_verified precondition, requires documents uploaded, validates all enums, sets password, transitions to pending_verification
- Advanced profile self-edit (PATCH): rejects religion (locked, admin-only once set); other fields apply as partial update
- Service modes update: validates enum values, requires advanced_details_completed
- Selfie upload: rejects files > 10MB, stores at correct path
- Document upload: rejects > 10MB, enforces max 3 "other" docs, validates document_type enum
- Verification status GET: returns current status + rejection message

### Admin Module
- Dashboard stats: returns correct counts per status
- Caregiver list: pagination, sorting, all filters (status, qualification, expertise, language, service_mode, date range, search)
- Call verified: enforces pending_call precondition, sets timestamps, rejects wrong status
- Status change: enforces allowed transitions, rejects invalid transitions, requires rejection_message for rejected
- Edit caregiver profile: applies changes, creates audit log, does NOT change verification status
- Admin notes: upserts correctly, validates rate >= 0
- Acknowledge edits: enforces has_pending_edits=true precondition
- Phone change: validates format, rejects duplicates, updates user record
- Reset password (admin-initiated): enforces email exists on caregiver

### Notification Module
- FCM token storage: updates users.fcm_token
- Push dispatch: sends correct title/body per event type
- Handles missing/invalid FCM token gracefully (no crash)

### Audit Module
- Creates log entry with correct actor, target, action, entity_type, entity_id
- Captures before/after JSONB values
- Records IP address
- Audit log query: filters by user_id, target_user_id, action, date range

### Upload Module
- File size validation (reject > 10MB)
- Correct path construction: `{profile_id}/{document_type}.{ext}`
- Overwrite behavior for re-uploads (selfie, qualification, aadhaar)
- Sequential naming for "other" docs (other_1, other_2, other_3)
- Signed URL generation with 1-hour expiry

---

## 2. Integration Test Scenarios (API Endpoint Testing)

### Auth Endpoints
| Endpoint | Test |
|----------|------|
| POST /auth/register | 201 with valid payload; 409 with duplicate phone; 400 with invalid phone format |
| POST /auth/login/phone | 200 with registered phone; 404 with unknown phone; 401 if deactivated |
| POST /auth/login/email | 200 with correct creds; 401 with wrong password |
| POST /auth/refresh | 200 rotates token; 401 with revoked token |
| POST /auth/logout | 200 revokes token; subsequent refresh fails |
| POST /auth/forgot-password | 200 with valid email; 404 with unknown email; 400 if no email set |
| POST /auth/reset-password | 200 with valid token; 400 with expired token |

### Caregiver Endpoints
| Endpoint | Test |
|----------|------|
| GET /caregiver/profile | 200 returns full profile with signed URLs |
| PUT /caregiver/profile/basic | 200 updates fields; 400 with invalid values |
| PUT /caregiver/profile/advanced | 200 when call_verified + docs uploaded; 403 if not call_verified; 400 if docs missing |
| POST /caregiver/profile/selfie | 200 with valid file; 400 if > 10MB |
| POST /caregiver/profile/documents | 200 for each type; 400 on 4th "other" doc |
| GET /caregiver/verification-status | 200 returns current status |
| GET /caregiver/jobs | 200 returns active job listings |
| POST /caregiver/jobs/:id/respond | 200 records response; 400 on invalid response type |
| PUT /caregiver/fcm-token | 200 stores token |

### Admin Endpoints
| Endpoint | Test |
|----------|------|
| GET /admin/dashboard/stats | 200 with correct counts |
| GET /admin/caregivers | 200 with pagination; filters work correctly |
| GET /admin/caregivers/:id | 200 with full detail + signed URLs |
| PATCH /admin/caregivers/:id/call-verified | 200 from pending_call; 400 from other statuses |
| PATCH /admin/caregivers/:id/status | 200 for valid transitions; 400 for invalid ones |
| PUT /admin/caregivers/:id | 200 updates profile; does not change status |
| POST /admin/caregivers/:id/notes | 200 creates/updates notes |
| PATCH /admin/caregivers/:id/acknowledge-edits | 200 clears flag; 400 if no pending edits |
| PATCH /admin/caregivers/:id/phone | 200 with valid phone; 409 if phone taken; 400 if invalid format |
| POST /admin/caregivers/:id/reset-password | 200 if email set; 400 if no email |
| GET /admin/audit-logs | 200 with pagination and filters |

### Authorization Guards
- Caregiver token cannot access /admin/* endpoints (403)
- Admin token cannot access /caregiver/* endpoints (403)
- Expired token returns 401
- No token returns 401
- Deactivated admin cannot access any endpoint (401)

---

## 3. End-to-End Test Flows

### Flow 1: Complete Registration to Verification

1. POST /auth/register with valid data -> 201, get tokens
2. POST /caregiver/profile/selfie -> upload selfie
3. GET /caregiver/profile -> verify status is pending_call, advanced fields null
4. (Admin) PATCH /admin/caregivers/:id/call-verified -> status becomes call_verified
5. POST /caregiver/profile/documents (qualification) -> upload doc
6. POST /caregiver/profile/documents (aadhaar) -> upload doc
7. PUT /caregiver/profile/advanced with all required fields -> 200, status becomes pending_verification
8. (Admin) PATCH /admin/caregivers/:id/status { status: "in_process" } -> 200
9. (Admin) PATCH /admin/caregivers/:id/status { status: "verified" } -> 200
10. (Admin) PATCH /admin/caregivers/:id/make-available -> 200
11. (Admin) POST /admin/jobs -> 201, verify push sent to all caregivers
12. POST /caregiver/jobs/:id/respond { response: "accepted" } -> 200
13. Verify: audit_logs has entries for each step, push notifications were triggered at steps 4, 8, 9, 11

### Flow 2: Rejection and Re-submission

1. Complete steps 1-7 from Flow 1 (reach pending_verification)
2. (Admin) PATCH /admin/caregivers/:id/status { status: "rejected", rejection_message: "Aadhaar is blurry" }
3. GET /caregiver/verification-status -> status=rejected, rejection_message present
4. POST /caregiver/profile/documents (aadhaar) -> re-upload clearer doc
5. PUT /caregiver/profile/advanced -> re-submit (status resets to pending_verification)
6. (Admin) PATCH /admin/caregivers/:id/status { status: "verified" } -> 200
7. Verify: caregiver can now set availability

### Flow 3: Profile Edit with Pending Edits Acknowledgment

1. Complete full verification (Flow 1)
2. PUT /caregiver/profile/basic { age: 34 } -> 200, has_pending_edits=true
3. GET /caregiver/profile -> verify has_pending_edits=true, verification_status still "verified"
4. Caregiver continues using app normally (not blocked)
5. (Admin) GET /admin/caregivers -> filter by pending edits, find the caregiver
6. (Admin) GET /admin/caregivers/:id -> review changes in audit log
7. (Admin) PATCH /admin/caregivers/:id/acknowledge-edits -> 200, has_pending_edits=false
8. Verify: audit log records the acknowledgment

### Flow 4: Admin Phone Change for Recovery

1. Caregiver registered with phone +919876543210 (no email set, Stage 1 only)
2. Caregiver loses phone, contacts office
3. (Admin) PATCH /admin/caregivers/:id/phone { new_phone: "+919876500000" }
4. POST /auth/login/phone { phone: "+919876500000" } -> 200, login succeeds
5. POST /auth/login/phone { phone: "+919876543210" } -> 404, old phone no longer works
6. Verify: audit_logs records phone_changed with before/after values

---

## 4. Edge Cases to Cover

### Authentication Edge Cases
- Register with phone missing +91 prefix -> 400 (AUTH_001 format check)
- Register with phone that has 5 as first digit (invalid) -> 400
- Login immediately after registration (same phone) -> 200
- Use refresh token twice (replay attack) -> second use returns 401
- Login with deactivated account -> 401 (AUTH_004)
- Email login before advanced details (no password set) -> 401

### Profile Edge Cases
- Submit advanced details before call_verified -> 403 (PROFILE_008)
- Submit advanced details without uploading required docs -> 400 (PROFILE_017)
- Set terms_accepted=false in advanced details -> 400 (PROFILE_009)
- Age boundary: 17 -> rejected, 18 -> accepted, 65 -> accepted, 66 -> rejected
- Name with numbers or special chars -> 400 (PROFILE_020)
- Address exactly at 500 chars -> accepted; 501 chars -> rejected
- Upload 4th "other" document -> 400 (UPLOAD_003)
- Upload file exactly at 10MB -> accepted; 10MB + 1 byte -> rejected

### Admin Edge Cases
- Invalid status transition: rejected -> verified directly -> 400 (ADMIN_001)
- Invalid status transition: verified -> rejected directly -> 400 (ADMIN_001)
- Call-verify a caregiver not in pending_call -> 400 (ADMIN_002)
- Create admin with existing email -> 409 (ADMIN_003)
- Admin deactivates themselves -> 400 (ADMIN_005)
- Admin deactivates super_admin -> 400 (ADMIN_006)
- Rejection message > 1000 chars -> 400 (ADMIN_007)
- Reset password for caregiver without email -> 400 (ADMIN_008)
- Change phone to already-used number -> 409 (ADMIN_009)
- Acknowledge edits when has_pending_edits=false -> 400 (ADMIN_011)

### Availability Edge Cases
- Set availability before verification -> 403 (AVAIL_001)
- preferred_localities at 500 chars -> accepted; 501 -> rejected

### General Edge Cases
- Malformed JSON body -> 400 (GEN_001)
- Request to non-existent resource -> 404 (GEN_002)
- Pagination: page=0, limit=0, limit=101 -> 400 (GEN_005)
- Concurrent registration with same phone (race condition) -> one succeeds, one gets 409

---

## 5. Acceptance Criteria per Feature

### Registration (Stage 1)
- [ ] Caregiver can register with phone, name, gender, age, languages
- [ ] Duplicate phone is rejected with clear error
- [ ] Tokens (access + refresh) are returned on success
- [ ] Profile is created with status pending_call
- [ ] Selfie can be uploaded immediately after registration
- [ ] Audit log entry exists for registration

### Phone Call Verification
- [ ] Admin can mark caregiver as call_verified from pending_call
- [ ] Push notification is sent to caregiver
- [ ] Timestamp and admin ID are recorded
- [ ] Caregiver can now access advanced details form

### Advanced Details (Stage 2)
- [ ] Endpoint rejects if not call_verified
- [ ] Endpoint rejects if documents not uploaded
- [ ] All fields validated per spec enums
- [ ] Password is hashed and stored
- [ ] Status transitions to pending_verification
- [ ] Email is stored and must be unique
- [ ] Audit log and admin email notification triggered

### Document Upload
- [ ] Selfie, qualification, aadhaar each upload and overwrite correctly
- [ ] Max 3 "other" documents enforced
- [ ] 10MB limit enforced
- [ ] File paths stored (not full URLs)
- [ ] Signed URLs generated on retrieval with 1hr expiry

### Admin Verification Workflow
- [ ] All valid status transitions work
- [ ] All invalid transitions are rejected with ADMIN_001
- [ ] Rejection requires/stores rejection_message
- [ ] Push notification sent on each status change
- [ ] Email sent to caregiver on status change
- [ ] verified_at and verified_by recorded on verification

### Profile Editing (Post-Verification)
- [ ] Caregiver can edit basic fields and service modes
- [ ] has_pending_edits flag is set to true
- [ ] Verification status does NOT change
- [ ] Caregiver is NOT blocked from app usage
- [ ] Admin can see pending edits and acknowledge them
- [ ] Audit log captures before/after values

### Admin Phone Change
- [ ] Only admin can change phone (no caregiver self-service)
- [ ] New phone must be valid format and unique
- [ ] Old phone no longer works for login
- [ ] New phone works for login
- [ ] Audit log records the change

### Availability (Post-Verification)
- [ ] Only verified caregivers can set availability
- [ ] Text fields respect 500-char limit
- [ ] Audit log and admin notification triggered

### Admin Management (Super Admin)
- [ ] Super admin can create new admins
- [ ] Super admin can deactivate admins (soft delete)
- [ ] Cannot deactivate self or super_admin
- [ ] Deactivated admin cannot login

### Audit Logging
- [ ] Every state-changing action creates an audit entry
- [ ] Entries include actor, target, action, before/after, IP, timestamp
- [ ] Logs are queryable with filters (user, action, date range)
- [ ] Logs are immutable (no update/delete)
- [ ] Caregivers cannot access audit logs
