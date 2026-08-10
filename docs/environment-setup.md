# VitaCare - Environment Setup Guide

This guide walks a new developer through setting up the VitaCare project locally.

---

## 1. Prerequisites

Ensure the following are installed on your machine:

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 20 LTS | https://nodejs.org/ |
| npm | 10+ (ships with Node 20) | Included with Node.js |
| Flutter | 3.19+ | https://docs.flutter.dev/get-started/install |
| Dart | (bundled with Flutter) | Included with Flutter |
| Melos | Latest | `dart pub global activate melos` |

Verify installations:

```bash
node --version    # v20.x.x
flutter --version # 3.19+
dart --version
melos --version
```

---

## 2. Clone and Install

```bash
# Clone the repository
git clone <repository-url> vitacare
cd vitacare

# Install Flutter dependencies across all packages
melos bootstrap

# Install Node.js dependencies (API and shared TS packages)
npm install
```

`melos bootstrap` links all Flutter/Dart packages in the monorepo. `npm install` resolves workspaces for the NestJS API and any shared TypeScript packages.

---

## 3. Supabase Setup

1. Go to https://supabase.com and create a new project.
2. Once the project is created, navigate to **Settings > API** and copy:
   - **Project URL** (e.g., `https://xxxx.supabase.co`)
   - **anon (public) key**
   - **service_role (secret) key**
3. Navigate to **Settings > Database** and copy the **Connection string** (PostgreSQL URI).
4. Create a storage bucket:
   - Go to **Storage** in the Supabase dashboard.
   - Click **New bucket**.
   - Name: `caregiver-documents`
   - Set as **Private** (not public).

Place these values in `apps/api/.env` (see Section 6 below).

---

## 4. Firebase Setup

1. Go to https://console.firebase.google.com and create a new project.
2. Enable **Firebase Cloud Messaging (FCM)**:
   - Go to **Project Settings > Cloud Messaging** and ensure it is enabled.
3. Generate a service account key:
   - Go to **Project Settings > Service accounts**.
   - Click **Generate new private key**.
   - From the downloaded JSON, extract `project_id`, `private_key`, and `client_email` for env vars.
4. Add Android app:
   - Register with your package name.
   - Download `google-services.json` and place it in `apps/caregiver-app/android/app/`.
5. Add iOS app:
   - Register with your bundle ID.
   - Download `GoogleService-Info.plist` and place it in `apps/caregiver-app/ios/Runner/`.

---

## 5. Gmail App Password Setup

The API sends emails via Gmail SMTP using an App Password (not the account password).

1. Log in to `vitacasahealthindia@gmail.com` (or your designated sender account).
2. Enable **2-Step Verification**:
   - Go to https://myaccount.google.com/security
   - Under "Signing in to Google", enable 2-Step Verification.
3. Generate an App Password:
   - Go to https://myaccount.google.com/apppasswords
   - Select app: "Mail", device: "Other (VitaCare API)".
   - Copy the 16-character password.
4. Set `SMTP_PASSWORD` in your `.env` to this app password.

---

## 6. Environment Variables

Copy the example file and fill in your values:

```bash
cp apps/api/.env.example apps/api/.env
```

Edit `apps/api/.env` with the values from steps 3-5.

---

## 7. Database Migrations

Run the SQL migrations against your Supabase PostgreSQL instance:

```bash
# Option A: Via Supabase CLI
supabase db push

# Option B: Via psql directly
psql "$DATABASE_URL" -f migrations/001_initial_schema.sql
```

If using the Supabase dashboard, you can also paste migration SQL into the **SQL Editor**.

---

## 8. Seed Super Admin

Create the initial Super Admin user so you can access the admin dashboard:

```bash
cd apps/api
npm run seed:admin -- --password <your-secure-password>
```

This creates a super_admin user with the configured email and the password you provide. Store this password securely.

---

## 9. Run Locally

Open three terminal windows/tabs:

**Terminal 1 - API Server:**
```bash
cd apps/api
npm run start:dev
# Runs on http://localhost:3000
```

**Terminal 2 - Flutter Caregiver App:**
```bash
cd apps/caregiver-app
flutter run
```

**Terminal 3 - Admin Web Dashboard:**
```bash
cd apps/admin-web
flutter run -d chrome
```

---

## 10. Verify Setup Checklist

- [ ] `node --version` returns v20.x.x
- [ ] `flutter doctor` shows no critical errors
- [ ] `melos bootstrap` completes without errors
- [ ] `npm install` completes without errors
- [ ] `.env` file is populated with all required values
- [ ] API starts on port 3000 without errors
- [ ] Supabase project is accessible and storage bucket exists
- [ ] Database migrations have been applied (tables exist)
- [ ] Super Admin can log in to the admin dashboard
- [ ] Firebase is configured and FCM test notification works
- [ ] Emails send successfully (check with a test endpoint or seed flow)
