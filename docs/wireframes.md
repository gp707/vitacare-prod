# VitaCare — Screen Wireframes

Reference for developers. Mobile wireframes are ~40 chars wide (phone-sized). Web wireframes are ~80 chars wide.

---

## Mobile App Screens

---

### 1. Splash (`/`)

```
+--------------------------------------+
|                                      |
|                                      |
|                                      |
|            [VITACARE LOGO]           |
|                                      |
|            Loading...                |
|                                      |
|                                      |
|                                      |
+--------------------------------------+
```

**Behavior:** Shows app logo for 1-2 seconds. Checks stored JWT token, validates/refreshes if exists.

**Navigation:**
- No token -> Login
- Valid token -> Route by `verification_status`

---

### 2. Login (`/login`)

```
+--------------------------------------+
|            VitaCare                   |
|                                      |
|  Phone Number                        |
|  +----------------------------------+|
|  | +91 |  9876543210               ||
|  +----------------------------------+|
|                                      |
|  +----------------------------------+|
|  |            LOGIN                 ||
|  +----------------------------------+|
|                                      |
|                                      |
|       New here? Register             |
|                                      |
+--------------------------------------+
```

**Behavior:** Phone number input with +91 prefix fixed. Login triggers auth flow. On success, route by verification_status.

**Navigation:**
- "Register" link -> Registration
- Successful login -> Route by status

---

### 3. Registration (`/register`)

```
+--------------------------------------+
|          < Back     Register         |
|--------------------------------------|
|  First Name                          |
|  +----------------------------------+|
|  |                                  ||
|  +----------------------------------+|
|  Last Name                           |
|  +----------------------------------+|
|  |                                  ||
|  +----------------------------------+|
|  Phone                               |
|  +----------------------------------+|
|  | +91 |                            ||
|  +----------------------------------+|
|  Gender                              |
|  +----------------------------------+|
|  | Select...               v        ||
|  +----------------------------------+|
|  Age                                 |
|  +----------------------------------+|
|  |                                  ||
|  +----------------------------------+|
|  Languages                           |
|  [Hindi] [English] [+Add]           |
|                                      |
|  Selfie                              |
|  +----------------------------------+|
|  |  [Camera Icon]                   ||
|  |  Take Selfie                     ||
|  +----------------------------------+|
|                                      |
|  +----------------------------------+|
|  |          REGISTER                ||
|  +----------------------------------+|
+--------------------------------------+
```

**Behavior:** All fields required. Selfie opens camera only (no gallery). Languages are multi-select chips. Gender is dropdown (male/female/other). Age must be 18-65.

**Navigation:**
- "Back" -> Login
- Successful registration -> Pending Call

---

### 4. Pending Call (`/pending-call`)

```
+--------------------------------------+
|            VitaCare                   |
|--------------------------------------|
|                                      |
|         [Phone Icon]                 |
|                                      |
|   Thank you for registering!         |
|                                      |
|   You will receive a call from       |
|   our office shortly to verify       |
|   your phone number.                 |
|                                      |
|   ---------------------------------- |
|   Name:  Priya Sharma                |
|   Phone: +91 9876543210             |
|   ---------------------------------- |
|                                      |
|       Pull down to refresh           |
|                                      |
+--------------------------------------+
```

**Behavior:** Waiting screen with no action buttons. Shows registered name and phone. Pull-to-refresh checks if status changed to `call_verified`.

**Navigation:**
- Status changes to `call_verified` -> Advanced Details Form
- No back navigation to Registration

---

### 5. Advanced Details Form (`/advanced-details`)

```
+--------------------------------------+
|       Advanced Details               |
|--------------------------------------|
|  Highest Qualification               |
|  +----------------------------------+|
|  | Select...               v        ||
|  +----------------------------------+|
|  Current Address                     |
|  +----------------------------------+|
|  |                                  ||
|  |                                  ||
|  +----------------------------------+|
|  Email                               |
|  +----------------------------------+|
|  |                                  ||
|  +----------------------------------+|
|  Password                            |
|  +----------------------------------+|
|  | ********                         ||
|  +----------------------------------+|
|  Expertise Areas                     |
|  [Elder Care] [Child Care] [+Add]   |
|                                      |
|  Service Modes                       |
|  [ ] Live-in                         |
|  [ ] 24hr Paying Guest              |
|  [ ] 12hr Paying Guest              |
|                                      |
|  [x] I agree to Terms & Conditions  |
|                                      |
|  +----------------------------------+|
|  |      UPLOAD DOCUMENTS            ||
|  +----------------------------------+|
|  +----------------------------------+|
|  |          SUBMIT                  ||
|  +----------------------------------+|
+--------------------------------------+
```

**Behavior:** All fields required. Submit disabled until all required docs uploaded and fields filled. Expertise is multi-select chips. Password min 6 chars.

**Navigation:**
- "Upload Documents" -> Document Upload
- "Submit" -> Verification Status (status becomes `pending_verification`)

---

### 6. Document Upload (`/documents`)

```
+--------------------------------------+
|    < Back       Documents            |
|--------------------------------------|
|                                      |
|  Qualification Document *            |
|  +----------------------------------+|
|  |  [Upload Icon]                   ||
|  |  Tap to upload                   ||
|  +----------------------------------+|
|  [====75%=====       ] uploading...  |
|                                      |
|  Aadhaar Card *                      |
|  +----------------------------------+|
|  |  [Preview Thumbnail]            ||
|  |  aadhaar_front.jpg  [X]         ||
|  +----------------------------------+|
|                                      |
|  Other Documents (Optional)          |
|  +----------------------------------+|
|  |  [Upload Icon] Slot 1           ||
|  +----------------------------------+|
|  +----------------------------------+|
|  |  [Upload Icon] Slot 2           ||
|  +----------------------------------+|
|  +----------------------------------+|
|  |  [Upload Icon] Slot 3           ||
|  +----------------------------------+|
|                                      |
|  +----------------------------------+|
|  |            DONE                  ||
|  +----------------------------------+|
+--------------------------------------+
```

**Behavior:** Three sections. Qualification and Aadhaar are required. Other documents optional (max 3). Each upload shows progress. Preview shown after successful upload.

**Navigation:**
- "Done" / Back -> Advanced Details Form

---

### 7. Verification Status (`/verification-status`)

```
+--------------------------------------+
|         Verification Status          |
|--------------------------------------|
|                                      |
|  Progress:                           |
|                                      |
|  (*)-----(*)-----(o)-----( )         |
|  Registered  Submitted  Review  Done |
|                                      |
|  ----------------------------------- |
|                                      |
|  Your profile is under review.       |
|  We'll notify you once verified.     |
|                                      |
|  Current Status:                     |
|  [PENDING VERIFICATION]             |
|                                      |
|  ----------------------------------- |
|                                      |
|       Pull down to refresh           |
|                                      |
+--------------------------------------+
```

**Behavior:** Shows current status with timeline/stepper visual. Pull-to-refresh to check for status updates. Applies to both `pending_verification` and `in_process` statuses.

**Navigation:**
- Status becomes `verified` -> Home
- Status becomes `rejected` -> Rejection Details

---

### 8. Rejection Details (`/rejection`)

```
+--------------------------------------+
|         Profile Rejected             |
|--------------------------------------|
|                                      |
|         [Warning Icon]               |
|                                      |
|  Your profile was not approved.      |
|                                      |
|  Reason from admin:                  |
|  ----------------------------------- |
|  "Qualification document is not      |
|   clear. Please upload a higher      |
|   resolution scan."                  |
|  ----------------------------------- |
|                                      |
|                                      |
|  +----------------------------------+|
|  |      EDIT & RESUBMIT            ||
|  +----------------------------------+|
|                                      |
+--------------------------------------+
```

**Behavior:** Displays admin rejection message. Caregiver can edit and resubmit their profile.

**Navigation:**
- "Edit & Resubmit" -> Edit Advanced Profile

---

### 9. Home (`/home`)

```
+--------------------------------------+
|  VitaCare                    [Gear]  |
|--------------------------------------|
|                                      |
|  Welcome, Priya!                     |
|                                      |
|  +----------------------------------+|
|  | Status: [VERIFIED]              ||
|  +----------------------------------+|
|                                      |
|  +----------------------------------+|
|  | Availability                     ||
|  | Live-in | Available from 15 Aug ||
|  +----------------------------------+|
|                                      |
|                                      |
|                                      |
|--------------------------------------|
| [Home]    [Profile]   [Availability] |
+--------------------------------------+
```

**Behavior:** Welcome screen for verified caregivers. Shows verification badge and availability summary. Bottom navigation bar shown only for verified status.

**Navigation:**
- Bottom nav: Profile, Availability
- Gear icon -> Settings

---

### 10. Profile View (`/profile`)

```
+--------------------------------------+
|  < Back       Profile        [Edit]  |
|--------------------------------------|
|        [Selfie Photo]                |
|        Priya Sharma                  |
|--------------------------------------|
|  BASIC INFO                          |
|  Phone:    +91 9876543210           |
|  Gender:   Female                    |
|  Age:      28                        |
|  Languages: Hindi, English           |
|--------------------------------------|
|  PROFESSIONAL                        |
|  Qualification: BSc Nursing          |
|  Expertise: Elder Care, Child Care   |
|  Service Modes: Live-in, 12hr PG    |
|--------------------------------------|
|  CONTACT                             |
|  Email: priya@email.com             |
|  Address: 42, MG Road, Bangalore    |
|--------------------------------------|
|  DOCUMENTS                           |
|  Qualification: [View]              |
|  Aadhaar: [View]                    |
|  Other: 2 files [View]              |
|--------------------------------------|
| [Home]    [Profile]   [Availability] |
+--------------------------------------+
```

**Behavior:** Read-only display of all profile information. Edit button navigates to edit screens.

**Navigation:**
- "Edit" -> Edit Basic Profile
- Back -> Home (if verified) or previous screen

---

### 11. Edit Basic Profile (`/profile/edit-basic`)

```
+--------------------------------------+
|  < Back    Edit Basic Profile        |
|--------------------------------------|
|  +----------------------------------+|
|  | (i) Changes will be reviewed by ||
|  |     admin. Status not affected. ||
|  +----------------------------------+|
|                                      |
|  First Name                          |
|  +----------------------------------+|
|  | Priya                            ||
|  +----------------------------------+|
|  Last Name                           |
|  +----------------------------------+|
|  | Sharma                           ||
|  +----------------------------------+|
|  Gender                              |
|  +----------------------------------+|
|  | Female                  v        ||
|  +----------------------------------+|
|  Age                                 |
|  +----------------------------------+|
|  | 28                               ||
|  +----------------------------------+|
|  Languages                           |
|  [Hindi] [English] [+Add]           |
|                                      |
|  +----------------------------------+|
|  |            SAVE                  ||
|  +----------------------------------+|
+--------------------------------------+
```

**Behavior:** Editable fields: First Name, Last Name, Gender, Age, Languages. Info banner explains changes are reviewed. Save sends update to API.

**Navigation:**
- "Save" -> Profile View (on success)
- Back -> Profile View

---

### 12. Edit Advanced Profile (`/profile/edit-advanced`)

```
+--------------------------------------+
|  < Back   Edit Advanced Profile      |
|--------------------------------------|
|  +----------------------------------+|
|  | (i) Changes will be reviewed by ||
|  |     admin. Status not affected. ||
|  +----------------------------------+|
|                                      |
|  Highest Qualification               |
|  +----------------------------------+|
|  | BSc Nursing              v       ||
|  +----------------------------------+|
|  Current Address                     |
|  +----------------------------------+|
|  | 42, MG Road, Bangalore          ||
|  +----------------------------------+|
|  Expertise Areas                     |
|  [Elder Care] [Child Care] [+Add]   |
|                                      |
|  Service Modes                       |
|  [x] Live-in                         |
|  [ ] 24hr Paying Guest              |
|  [x] 12hr Paying Guest              |
|                                      |
|  Documents                           |
|  Qualification  [Re-upload]         |
|  Aadhaar        [Re-upload]         |
|  Other          [Re-upload]         |
|                                      |
|  +----------------------------------+|
|  |            SAVE                  ||
|  +----------------------------------+|
+--------------------------------------+
```

**Behavior:** Edit qualification, address, expertise, service modes. Re-upload documents. Only accessible if `advanced_details_completed` is true. Info banner explains review process.

**Navigation:**
- "Save" -> Profile View (on success)
- Back -> Profile View or Rejection Details

---

### 13. Availability (`/availability`)

```
+--------------------------------------+
|  < Back       Availability           |
|--------------------------------------|
|  +----------------------------------+|
|  | (i) Updating availability does  ||
|  |     not affect verification.    ||
|  +----------------------------------+|
|                                      |
|  Preferred Localities                |
|  +----------------------------------+|
|  | Koramangala, Indiranagar        ||
|  +----------------------------------+|
|                                      |
|  Notes                               |
|  +----------------------------------+|
|  | Prefer morning shifts           ||
|  |                                  ||
|  +----------------------------------+|
|                                      |
|  Service Modes                       |
|  [x] Live-in                         |
|  [ ] 24hr Paying Guest              |
|  [x] 12hr Paying Guest              |
|                                      |
|  +----------------------------------+|
|  |            SAVE                  ||
|  +----------------------------------+|
|--------------------------------------|
| [Home]    [Profile]   [Availability] |
+--------------------------------------+
```

**Behavior:** Date picker for available from. Text inputs for localities and notes. Service modes editable. Only accessible when status is `verified`.

**Navigation:**
- "Save" -> stays on screen with success toast
- Bottom nav to other screens

---

### 14. Settings (`/settings`)

```
+--------------------------------------+
|  < Back        Settings              |
|--------------------------------------|
|                                      |
|  ACCOUNT                             |
|  +----------------------------------+|
|  | Change Password              >  ||
|  +----------------------------------+|
|                                      |
|  +----------------------------------+|
|  |            LOGOUT                ||
|  +----------------------------------+|
|                                      |
|                                      |
|                                      |
|  ----------------------------------- |
|  App Version: 1.0.0                  |
|                                      |
+--------------------------------------+
```

**Behavior:** Change password (only if email is set on profile). Logout clears token and navigates to Login. Shows app version.

**Navigation:**
- "Change Password" -> password change flow
- "Logout" -> Login screen

---

## Admin Dashboard Screens (Web)

---

### 1. Admin Login (`/login`)

```
+------------------------------------------------------------------------------+
|                                                                              |
|                                                                              |
|                          +----------------------------+                      |
|                          |        VitaCare Admin      |                      |
|                          |----------------------------|                      |
|                          |                            |                      |
|                          |  Email                     |                      |
|                          |  +----------------------+  |                      |
|                          |  | admin@vitacare.com   |  |                      |
|                          |  +----------------------+  |                      |
|                          |                            |                      |
|                          |  Password                  |                      |
|                          |  +----------------------+  |                      |
|                          |  | ********             |  |                      |
|                          |  +----------------------+  |                      |
|                          |                            |                      |
|                          |  +----------------------+  |                      |
|                          |  |       LOGIN          |  |                      |
|                          |  +----------------------+  |                      |
|                          |                            |                      |
|                          +----------------------------+                      |
|                                                                              |
+------------------------------------------------------------------------------+
```

**Behavior:** Email and password login. On success, navigates to Dashboard.

**Navigation:**
- Successful login -> Dashboard

---

### 2. Dashboard (`/dashboard`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Admin Name v]   |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| D |  DASHBOARD                                                               |
| a |                                                                          |
| s |  +------------+ +------------+ +------------+ +------------+            |
| h |  | Total      | | Pending    | | Call       | | Pending    |            |
| b |  | Caregivers | | Call       | | Verified   | | Verif.     |            |
| o |  |     142    | |      8     | |     12     | |      5     |            |
| a |  +------------+ +------------+ +------------+ +------------+            |
| r |                                                                          |
| d |  +------------+ +------------+ +------------+ +------------+            |
|   |  | In Process | | Verified   | | Rejected   | | Pending    |            |
| C |  |            | |            | |            | | Edits      |            |
| a |  |      3     | |     98     | |     16     | |      4     |            |
| r |  +------------+ +------------+ +------------+ +------------+            |
| e |                                                                          |
| g |  +------------+ +------------+                                           |
| i |  | New (24h)  | | New (7d)   |                                           |
| v |  |      2     | |     11     |                                           |
| e |  +------------+ +------------+                                           |
| r |                                                                          |
| s |                                                                          |
|   |                                                                          |
| A |                                                                          |
| u |                                                                          |
| d |                                                                          |
| i |                                                                          |
| t |                                                                          |
|   |                                                                          |
| S |                                                                          |
| e |                                                                          |
| t |                                                                          |
+---+--------------------------------------------------------------------------+
```

**Behavior:** Stats cards show real-time counts. Cards are clickable and navigate to Caregiver List with that status pre-filtered. "Pending Edits" shows verified caregivers who edited profiles needing review.

**Navigation:**
- Click any card -> Caregiver List (filtered)
- Sidebar links to all sections

---

### 3. Caregiver List (`/caregivers`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Admin Name v]   |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| S |  CAREGIVERS                              [Last 24h] [Last 7d] [Last 30d]|
| i |                                                                          |
| d |  Filters:  [Search........]  Status [All v]  Qualification [All v]      |
| e |            Expertise [All v]  Language [All v]  Mode [All v]             |
| b |            From [__/__/____]  To [__/__/____]        [Apply] [Clear]     |
| a |  ------------------------------------------------------------------------|
| r |  | Name       | Phone        | Gender | Age | Qual.  | Modes | Status  ||
|   |  |------------|--------------|--------|-----|--------|-------|---------|  |
|   |  | Priya S.   | +91 98765..  | F      | 28  | BSc N. | LI,12 | Verified|  |
|   |  | Ramesh K.  | +91 87654..  | M      | 35  | 10th   | 24hr  | Pending |  |
|   |  | Anita M.   | +91 76543..  | F      | 42  | 12th   | LI    | In Proc |  |
|   |  | Suresh B.  | +91 65432..  | M      | 31  | GNM    | 12,24 | Rejected|  |
|   |  | ...        | ...          | ...    | ... | ...    | ...   | ...     |  |
|   |  ------------------------------------------------------------------------|
|   |                                                                          |
|   |  Showing 1-25 of 142               [< Prev]  1  2  3  4  5  [Next >]   |
|   |                                                                          |
+---+--------------------------------------------------------------------------+
```

**Behavior:** Sortable data table with columns: Name, Phone, Gender, Age, Qualification, Service Modes, Status, Registered. Collapsible filter panel with search, dropdowns, date range. Quick filter chips. Real-time: new rows appear automatically, status badges update live.

**Navigation:**
- Click row -> Caregiver Detail
- Sidebar navigation

---

### 4. Caregiver Detail (`/caregivers/:id`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Admin Name v]   |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| S |  < Back to List                                                          |
| i |                                                                          |
| d |  +-------------------------------------------------------------------+  |
| e |  | [Photo]  Priya Sharma        +91 9876543210                        |  |
| b |  |          [PENDING VERIFICATION]     Registered: 01 Aug 2026       |  |
| a |  +-------------------------------------------------------------------+  |
| r |                                                                          |
|   |  Actions: [Mark Call Verified] [Start Review] [Approve] [Reject]        |
|   |           [Change Phone]                                                 |
|   |                                                                          |
|   |  [Profile]  [Documents]  [Notes]  [Audit History]                       |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
|   |  PROFILE TAB:                                                            |
|   |  --------------------------------------------------------------------|  |
|   |  | Field             | Value                                         |  |
|   |  |-------------------|-----------------------------------------------|  |
|   |  | First Name        | Priya                                         |  |
|   |  | Last Name         | Sharma                                        |  |
|   |  | Gender            | Female                                        |  |
|   |  | Age               | 28                                            |  |
|   |  | Languages         | Hindi, English                                |  |
|   |  | Qualification     | BSc Nursing                                   |  |
|   |  | Email             | priya@email.com                               |  |
|   |  | Address           | 42, MG Road, Bangalore                        |  |
|   |  | Expertise         | Elder Care, Child Care                        |  |
|   |  | Service Modes     | Live-in, 12hr PG                              |  |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
+---+--------------------------------------------------------------------------+
```

#### Documents Tab

```
|   |  DOCUMENTS TAB:                                                          |
|   |  --------------------------------------------------------------------|  |
|   |  Qualification Document                                                  |
|   |  +-----------------------------------------------+                      |
|   |  |                                               |                      |
|   |  |        [Document Preview/Image]               |                      |
|   |  |                                               |                      |
|   |  +-----------------------------------------------+  [Download]          |
|   |                                                                          |
|   |  Aadhaar Card                                                            |
|   |  +-----------------------------------------------+                      |
|   |  |                                               |                      |
|   |  |        [Document Preview/Image]               |                      |
|   |  |                                               |                      |
|   |  +-----------------------------------------------+  [Download]          |
|   |                                                                          |
|   |  Other Documents (2)                                                     |
|   |  +--------------------+  +--------------------+                          |
|   |  | [Thumbnail 1]      |  | [Thumbnail 2]      |                          |
|   |  +--------------------+  +--------------------+                          |
|   |  [Download All]                                                          |
```

#### Notes Tab

```
|   |  NOTES TAB:                                                              |
|   |  --------------------------------------------------------------------|  |
|   |  Internal Notes                                                          |
|   |  +----------------------------------------------------------------+     |
|   |  | Candidate seems experienced. Verified documents look good.     |     |
|   |  |                                                                |     |
|   |  +----------------------------------------------------------------+     |
|   |                                                                          |
|   |  Rates                                                                   |
|   |  Live-in:    +----------+  24hr PG:  +----------+                        |
|   |              | Rs 15000 |            | Rs 18000 |                        |
|   |              +----------+            +----------+                        |
|   |  12hr PG:   +----------+                                                 |
|   |              | Rs 10000 |                                                 |
|   |              +----------+                                                 |
|   |                                                                          |
|   |  Remarks                                                                 |
|   |  +----------------------------------------------------------------+     |
|   |  |                                                                |     |
|   |  +----------------------------------------------------------------+     |
|   |                                                                          |
|   |  [Save Notes]                                                            |
```

#### Audit History Tab

```
|   |  AUDIT HISTORY TAB:                                                      |
|   |  --------------------------------------------------------------------|  |
|   |  | Timestamp          | Actor        | Action           | Changes    |  |
|   |  |--------------------|--------------|------------------|------------|  |
|   |  | 01 Aug 14:32       | Admin Raj    | status_change    | [Expand]   |  |
|   |  | 01 Aug 10:15       | Caregiver    | profile_update   | [Expand]   |  |
|   |  | 31 Jul 09:00       | System       | registered       | [Expand]   |  |
|   |  --------------------------------------------------------------------|  |
```

#### Reject Modal

```
|   |  +-------------------------------------------+                           |
|   |  |  Reject Caregiver                    [X]  |                           |
|   |  |-------------------------------------------|                           |
|   |  |                                           |                           |
|   |  |  Rejection Message (optional):            |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |  | Document not clear enough...        |  |                           |
|   |  |  |                                     |  |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |                                           |                           |
|   |  |           [Cancel]  [Confirm Reject]      |                           |
|   |  +-------------------------------------------+                           |
```

**Behavior:** Header shows name, phone, status badge, registration date. Tabs for Profile, Documents, Notes, Audit History. Action buttons shown based on status:
- `pending_call`: "Mark Call Verified"
- `pending_verification`: "Start Review", "Approve", "Reject"
- `in_process`: "Approve", "Reject"
- `verified`/`rejected`: No status actions

"Change Phone" opens modal for account recovery.

**Navigation:**
- Back -> Caregiver List
- Action buttons update status in-place

---

### 5. Audit Logs (`/audit-logs`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Admin Name v]   |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| S |  AUDIT LOGS                                                              |
| i |                                                                          |
| d |  Filters: Action [All v]  Actor [All v]  Target [________]              |
| e |           From [__/__/____]  To [__/__/____]      [Apply] [Clear]       |
| b |                                                                          |
| a |  --------------------------------------------------------------------|  |
| r |  | Timestamp        | Actor       | Target      | Action      | Det. |  |
|   |  |------------------|-------------|-------------|-------------|------|  |
|   |  | 01 Aug 14:32:10  | Admin Raj   | Priya S.    | status_chg  |  [v] |  |
|   |  |   Before: pending_verification  After: in_process                 |  |
|   |  |------------------|-------------|-------------|-------------|------|  |
|   |  | 01 Aug 14:30:05  | Caregiver   | Self        | profile_upd |  [v] |  |
|   |  |------------------|-------------|-------------|-------------|------|  |
|   |  | 01 Aug 12:00:00  | Admin Raj   | Ramesh K.   | call_verif  |  [>] |  |
|   |  |------------------|-------------|-------------|-------------|------|  |
|   |  | 01 Aug 09:15:22  | System      | Anita M.    | registered  |  [>] |  |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
|   |  Showing 1-25 of 538              [< Prev]  1  2  3  ... 22  [Next >]   |
|   |                                                                          |
+---+--------------------------------------------------------------------------+
```

**Behavior:** Data table with columns: Timestamp, Actor, Target, Action, Changes. Filters by action type, actor, target, date range. Expandable rows show before/after JSON values. No export functionality.

**Navigation:**
- Sidebar navigation only
- Expandable rows inline

---

### 6. Admin Management (`/admins`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Super Admin v]  |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| S |  ADMIN MANAGEMENT                                    [+ Create Admin]    |
| i |                                                                          |
| d |  --------------------------------------------------------------------|  |
| e |  | Name             | Email                  | Status    | Actions    |  |
| b |  |------------------|------------------------|-----------|------------|  |
| a |  | Raj Kumar        | raj@vitacare.com       | Active    | [Deactivate]| |
| r |  | Neha Patel       | neha@vitacare.com      | Active    | [Deactivate]| |
|   |  | Amit Shah        | amit@vitacare.com      | Inactive  | --         |  |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
+---+--------------------------------------------------------------------------+
```

#### Create Admin Modal

```
|   |  +-------------------------------------------+                           |
|   |  |  Create Admin Account               [X]  |                           |
|   |  |-------------------------------------------|                           |
|   |  |                                           |                           |
|   |  |  Name                                     |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |  |                                     |  |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |                                           |                           |
|   |  |  Email                                    |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |  |                                     |  |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |                                           |                           |
|   |  |  Password                                 |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |  |                                     |  |                           |
|   |  |  +-------------------------------------+  |                           |
|   |  |                                           |                           |
|   |  |            [Cancel]  [Create]             |                           |
|   |  +-------------------------------------------+                           |
```

**Behavior:** Super Admin only. Lists all admin accounts with name, email, status. "Create Admin" button opens modal form. Deactivate button with confirmation dialog (soft-delete). Not visible to non-super-admin users.

**Navigation:**
- Sidebar navigation
- Modals for create/deactivate

---

### 7. Admin Settings (`/settings`)

```
+------------------------------------------------------------------------------+
| [=] VitaCare Admin                                          [Admin Name v]   |
|---+--------------------------------------------------------------------------|
|   |                                                                          |
| S |  SETTINGS                                                                |
| i |                                                                          |
| d |  Account                                                                 |
| e |  --------------------------------------------------------------------|  |
| b |  |  Name:   Raj Kumar                                                |  |
| a |  |  Email:  raj@vitacare.com                                         |  |
| r |  |  Role:   Admin                                                    |  |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
|   |  Change Password                                                         |
|   |  --------------------------------------------------------------------|  |
|   |  |  Current Password  +--------------------------------------+       |  |
|   |  |                    | ********                              |       |  |
|   |  |                    +--------------------------------------+       |  |
|   |  |  New Password      +--------------------------------------+       |  |
|   |  |                    |                                      |       |  |
|   |  |                    +--------------------------------------+       |  |
|   |  |  Confirm Password  +--------------------------------------+       |  |
|   |  |                    |                                      |       |  |
|   |  |                    +--------------------------------------+       |  |
|   |  |                                                                   |  |
|   |  |                                       [Update Password]           |  |
|   |  --------------------------------------------------------------------|  |
|   |                                                                          |
|   |  [Logout]                                                                |
|   |                                                                          |
+---+--------------------------------------------------------------------------+
```

**Behavior:** Shows current admin account info. Change password form with current, new, confirm fields. Logout button clears session.

**Navigation:**
- "Logout" -> Login screen
- Sidebar navigation

---

## Navigation Summary

### Mobile App Flow

```
Splash
  |
  +-- [no token] --> Login <--> Registration
  |
  +-- [token] --> Route by status:
                    |
                    +-- pending_call ---------> Pending Call
                    +-- call_verified --------> Advanced Details <-> Document Upload
                    +-- pending_verification -> Verification Status
                    +-- in_process -----------> Verification Status
                    +-- rejected -------------> Rejection Details -> Edit Advanced Profile
                    +-- verified -------------> Home
                                                 |
                                                 +-- Profile View -> Edit Basic / Edit Advanced
                                                 +-- Availability
                                                 +-- Settings
```

### Admin Web Sidebar

```
+-------------------+
| Dashboard         |  <- All admins
| Caregivers        |  <- All admins
| Audit Logs        |  <- All admins
| Admin Management  |  <- Super Admin only
| Settings          |  <- All admins
+-------------------+
```
