# ADR-001: Custom JWT Over Supabase Auth

**Date:** 2026-08-01  
**Status:** Accepted

## Context

Supabase Auth provides built-in authentication flows including phone-based OTP login. However, our requirements for Stage 1 specify phone-only login without OTP verification. Supabase Auth does not support phone login without sending an OTP — it always requires a verification code sent via SMS.

Additionally, Supabase Auth's phone OTP depends on a configured SMS provider (Twilio, etc.), adding cost and complexity. Our target users (caregivers) have their phone numbers verified via an office call, making SMS-based OTP redundant.

## Decision

We will implement custom JWT-based authentication for all users (caregivers, admins, super admins). Supabase will be used only for its Database (PostgreSQL), Storage, and Realtime capabilities — not for authentication.

The API server (NestJS) will:
- Issue JWTs signed with a server-side secret (`JWT_SECRET`)
- Handle password hashing with bcrypt (for admins and Stage 3+ caregivers)
- Manage access token and refresh token lifecycle
- Enforce role-based access via custom guards

## Consequences

**Positive:**
- Full control over authentication flow, allowing phone-only login without OTP
- No dependency on external SMS providers for Stage 1
- Flexibility to add password-based login in Stage 3 without changing auth infrastructure
- No Supabase Auth cost (free tier phone auth is limited)

**Negative:**
- We must implement and maintain password hashing, token issuance, token rotation, and refresh token logic ourselves
- We must handle token expiration, revocation, and security best practices manually
- Cannot leverage Supabase Row Level Security policies tied to `auth.uid()` — must use service role key and enforce access in application code
