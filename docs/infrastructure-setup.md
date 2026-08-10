# VitaCare — Infrastructure Setup Guide

## Overview

| Service | Purpose | Cost |
|---------|---------|------|
| Supabase | Database (PostgreSQL) + File Storage | Free tier (sufficient for V1) |
| Railway / Render | Host NestJS backend | ~$5-7/month |
| Firebase | Push notifications | Free |
| Gmail | Email sending (SMTP) | Free (existing account) |

**Total monthly cost: ~$5-7/month** (can start on free tiers for everything during development)

---

## 1. Supabase Setup

### What Supabase gives you:
- PostgreSQL database (where all data lives)
- File storage (caregiver documents, selfies)
- Realtime (live admin dashboard updates)
- Free tier: 500MB database, 1GB storage, 50MB file uploads

### Step-by-step:

**A. Create account & project:**
1. Go to [supabase.com](https://supabase.com)
2. Sign up (use GitHub or email)
3. Click "New Project"
4. Name: `vitacare-prod`
5. Database password: (save this — you'll need it)
6. Region: Choose closest to users (e.g., Mumbai `ap-south-1` if available, otherwise Singapore)
7. Click "Create new project" — wait 2 minutes

**B. Get your keys (Project Settings → API):**
```
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...        (public, safe for admin web app)
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...   (secret, backend only — NEVER expose to clients)
```

**C. Get database connection string (Project Settings → Database):**
```
DATABASE_URL=postgresql://postgres:[YOUR-PASSWORD]@db.xxxxxxxxxxxx.supabase.co:5432/postgres
```

**D. Create storage bucket:**
1. Go to Storage (left sidebar)
2. Click "New bucket"
3. Name: `caregiver-documents`
4. Public: **OFF** (private — we use signed URLs)
5. File size limit: 10MB

**E. Run database migrations:**
1. Go to SQL Editor (left sidebar)
2. Paste each migration file (001 through 010) from `supabase/migrations/` and run them in order
3. Or use Supabase CLI locally:
```bash
npm install -g supabase
supabase login
supabase link --project-ref xxxxxxxxxxxx
supabase db push
```

**F. Enable Realtime (for admin dashboard):**
1. Go to Database → Replication
2. Enable replication for tables: `caregiver_profiles`, `jobs`, `job_responses`
3. This allows admin dashboard to get live updates

### Supabase free tier limits:

| Resource | Free Limit | Enough for V1? |
|----------|-----------|----------------|
| Database | 500MB | Yes (thousands of caregivers) |
| Storage | 1GB | Yes (~100 caregivers × 5 docs × 2MB avg) |
| File uploads | 50MB per file | Yes (we limit to 10MB) |
| API requests | Unlimited | Yes |
| Realtime connections | 200 concurrent | Yes |
| Bandwidth | 2GB/month | Yes for V1 scale |

**When to upgrade:** If you exceed 500 caregivers with full documents, upgrade to Pro ($25/month for 8GB database + 100GB storage).

---

## 2. NestJS Backend Hosting

### Options (ranked by ease):

| Platform | Cost | Setup Difficulty | Best For |
|----------|------|-----------------|----------|
| **Railway** | $5/month | Very easy | Recommended for V1 |
| Render | $7/month | Easy | Alternative |
| DigitalOcean App Platform | $5/month | Medium | If you want more control |
| AWS EC2 | $5-15/month | Hard | Overkill for V1 |

### Recommended: Railway

**Why Railway:**
- Deploy from GitHub (auto-deploy on push)
- Free tier: $5 credit/month (enough for small apps)
- Easy environment variables setup
- Built-in logs and monitoring
- Cron job support (for daily availability reminder)

**Step-by-step:**

**A. Prepare your code:**

Your `apps/api/package.json` needs:
```json
{
  "scripts": {
    "build": "nest build",
    "start:prod": "node dist/main"
  }
}
```

Add a `Procfile` at `apps/api/`:
```
web: npm run start:prod
```

**B. Sign up & deploy:**
1. Go to [railway.app](https://railway.app)
2. Sign up with GitHub
3. Click "New Project" → "Deploy from GitHub repo"
4. Select your repository
5. Set root directory: `apps/api`
6. Railway auto-detects Node.js and runs `npm run build` then `npm run start:prod`

**C. Set environment variables (Railway dashboard → Variables):**
```
# Supabase
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...
DATABASE_URL=postgresql://postgres:password@db.xxxxxxxxxxxx.supabase.co:5432/postgres

# JWT
JWT_SECRET=generate-a-random-64-char-string-here
# Admin web only — caregiver-app access tokens never expire.
JWT_ACCESS_TOKEN_TTL=15552000
JWT_REFRESH_TOKEN_TTL=2592000

# Firebase
FIREBASE_PROJECT_ID=vitacare-prod
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@vitacare-prod.iam.gserviceaccount.com

# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=vitacasahealthindia@gmail.com
SMTP_PASSWORD=xxxx-xxxx-xxxx-xxxx

# App
API_PORT=3000
NODE_ENV=production
ADMIN_NOTIFICATION_EMAIL=vitacasahealthindia@gmail.com
```

**D. Get your API URL:**
- Railway gives you: `https://vitacare-api-production.up.railway.app`
- Or set custom domain: `api.vitacasahealth.in`

**E. Set up daily cron (for availability reminder):**
- Railway supports cron jobs via their "Cron" service
- Or add `node-cron` in your NestJS app:
```typescript
// In notification module
@Injectable()
export class DailyReminderService {
  @Cron('0 8 * * *') // 8 AM daily
  async sendDailyAvailabilityReminder() {
    // Query available/unavailable caregivers
    // Send batch push notification
  }
}
```

---

## 3. Firebase Setup (Push Notifications)

**A. Create project:**
1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. "Add project" → Name: "vitacare"
3. Disable Google Analytics (not needed for V1)
4. Create project

**B. Add Android app:**
1. Click Android icon
2. Package name: `com.vitacasahealth.caregiver`
3. App nickname: "VitaCare Caregiver"
4. Download `google-services.json`
5. Place at: `apps/caregiver-app/android/app/google-services.json`

**C. Get service account key (for backend):**
1. Project Settings → Service accounts
2. Click "Generate new private key"
3. Download JSON file
4. Copy `project_id`, `private_key`, `client_email` into your env vars

**D. Done.** Firebase Cloud Messaging is free and requires no billing setup.

---

## 4. Gmail SMTP Setup

**A. Enable 2-Factor Authentication:**
1. Go to [myaccount.google.com](https://myaccount.google.com) (logged in as vitacasahealthindia@gmail.com)
2. Security → 2-Step Verification → Turn on

**B. Generate App Password:**
1. Security → 2-Step Verification → App passwords
2. App: "Mail", Device: "Other (VitaCare Server)"
3. Copy the 16-character password
4. This is your `SMTP_PASSWORD` env var

**Limit:** 500 emails/day (more than enough for V1 admin notifications)

---

## 5. Domain Setup (Optional but Recommended)

If you want `api.vitacasahealth.in` instead of Railway's default URL:

1. In Railway: Settings → Domains → Add custom domain
2. Railway gives you a CNAME record
3. In your domain registrar (GoDaddy, Namecheap, etc.):
   - Add CNAME record: `api` → `[railway-provided-value]`
4. Wait 5-30 minutes for DNS propagation
5. Railway auto-provisions SSL certificate

---

## 6. Development vs Production

| | Development | Production |
|--|-------------|-----------|
| Database | Supabase (same, or separate project) | Supabase Pro ($25/mo when needed) |
| Backend | `localhost:3000` | Railway ($5/mo) |
| Firebase | Same project (use same keys) | Same project |
| Email | Same Gmail account | Same |
| Flutter app | `flutter run` (emulator/device) | APK/AAB signed build |
| Admin web | `flutter run -d chrome` | Deploy to Vercel/Netlify (free) |

### Admin Dashboard Hosting (Flutter Web):

After building: `flutter build web`

**Deploy to Vercel (free):**
1. Push the `apps/admin-web/build/web/` output to a GitHub repo (or same repo)
2. Connect to Vercel → auto-deploys
3. Custom domain: `admin.vitacasahealth.in`

**Or Netlify (free):**
1. Drag-drop the `build/web/` folder to Netlify
2. Custom domain setup same as above

---

## Quick Start Checklist

```
[ ] 1. Create Supabase project → get URL + keys
[ ] 2. Create storage bucket "caregiver-documents" (private)
[ ] 3. Run database migrations (SQL Editor or CLI)
[ ] 4. Enable Realtime on caregiver_profiles, jobs, job_responses
[ ] 5. Create Firebase project → add Android app → download google-services.json
[ ] 6. Generate Firebase service account key → copy to env vars
[ ] 7. Enable 2FA on Gmail → generate App Password
[ ] 8. Generate random JWT_SECRET (64+ characters)
[ ] 9. Deploy NestJS to Railway → set all env vars
[ ] 10. Point api.vitacasahealth.in to Railway (CNAME)
[ ] 11. Build Flutter web → deploy admin dashboard to Vercel
[ ] 12. Build APK → distribute to caregivers
```

---

## Monthly Costs Summary

| Service | Free Tier | When to Upgrade | Paid Tier |
|---------|-----------|-----------------|-----------|
| Supabase | 500MB DB, 1GB storage | 500+ caregivers | $25/mo (Pro) |
| Railway | $5 credit/month | After free credit | $5-10/mo |
| Firebase | Unlimited push | Never (for notifications) | Free |
| Gmail SMTP | 500 emails/day | Never (for V1 scale) | Free |
| Vercel (admin web) | 100GB bandwidth | Never (for V1) | Free |
| **TOTAL** | **$0-5/month** | | **$30-35/month at scale** |
