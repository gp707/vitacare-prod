# ADR-004: Phone-Only Login Without OTP

**Date:** 2026-08-01  
**Status:** Accepted

## Context

Target users for the caregiver app are individuals with 10th/12th pass education who may not be comfortable with OTP-based authentication flows. OTP flows require:
- Reading and entering a 6-digit code within a time window
- Handling SMS delivery failures
- Potential confusion between multiple SMS messages

In Stage 1, caregivers only submit profile information and documents for verification. There is no sensitive personal health data, financial data, or operational data at risk.

Phone number ownership is verified by an admin who calls the caregiver during the onboarding process (status: `pending_call` to `call_verified`).

## Decision

For Stage 1, caregivers will log in using only their phone number — no OTP, no password. The login flow is:

1. Caregiver enters their phone number.
2. API checks if the phone exists in the system (pre-registered by admin or self-registered).
3. If found, a JWT is issued immediately.
4. Phone ownership is verified out-of-band via an office call by an admin.

Passwords will be introduced in Stage 3 when caregivers access sensitive scheduling and payment data.

## Consequences

**Positive:**
- Extremely low friction for onboarding caregivers who may not be tech-savvy
- No SMS provider cost or integration complexity
- No failed OTP deliveries blocking user access
- Fast iteration on the MVP without auth complexity

**Negative:**
- Anyone who knows a caregiver's phone number could log in as them in Stage 1
- Acceptable because Stage 1 data (name, photo, documents) is not sensitive — it is information the caregiver is voluntarily submitting
- Must add password-based authentication before Stage 3 (when sensitive data becomes accessible)
- Cannot rely on phone auth alone for admin users (admins use email + password)
